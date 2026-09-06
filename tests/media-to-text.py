#!/usr/bin/env python3
"""Safety and CLI integration checks, without model downloads."""
import importlib.machinery
import importlib.util
from pathlib import Path
from types import SimpleNamespace, ModuleType
import tempfile
import json
import io
from contextlib import redirect_stderr, redirect_stdout
import sys
sys.dont_write_bytecode = True
import unittest
from unittest.mock import patch

path = Path(__file__).resolve().parents[1] / 'dot_local/bin/executable_media-to-text'
loader = importlib.machinery.SourceFileLoader('media_to_text', str(path))
spec = importlib.util.spec_from_loader(loader.name, loader)
module = importlib.util.module_from_spec(spec)
loader.exec_module(module)


class TranscriptionTests(unittest.TestCase):
    def test_auto_model_skips_incomplete_and_uses_local_only(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            for name in ['small', 'large-v3']:
                (root/name).mkdir()
                for f in ['model.bin', 'config.json', 'tokenizer.json', 'vocabulary.json']:
                    (root/name/f).write_text('test')
            (root/'small/model.bin').unlink()
            calls = []
            def resolve(name, **kwargs):
                calls.append((name, kwargs))
                return str(root/name)
            args = module.parser().parse_args(['sample.wav'])
            self.assertEqual(module.select_model(args, resolve), str(root/'large-v3'))
            self.assertTrue(all(kw == {'local_files_only': True} for _, kw in calls))

    def test_auto_model_no_cache_and_download_permission(self):
        def missing(*args, **kwargs):
            raise FileNotFoundError('not cached')
        args = module.parser().parse_args(['sample.wav'])
        with self.assertRaises(ValueError):
            module.select_model(args, missing)
        args.download_model = True
        self.assertEqual(module.select_model(args, missing), 'small')
        args.model = 'medium'
        self.assertEqual(module.select_model(args, missing), 'medium')

    def test_english_only_cache_is_not_used_for_auto_or_chinese(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            for f in ['model.bin', 'config.json', 'tokenizer.json', 'vocabulary.json']:
                (root/f).write_text('test')
            def resolve(name, **kwargs):
                if name == 'small.en': return str(root)
                raise FileNotFoundError(name)
            for language in ['auto', 'zh']:
                args = module.parser().parse_args(['sample.wav', '--language', language])
                with self.assertRaises(ValueError): module.select_model(args, resolve)
            args.language = 'en'
            self.assertEqual(module.select_model(args, resolve), str(root))

    def test_default_only_srt_and_all_formats(self):
        with tempfile.TemporaryDirectory() as tmp:
            source = Path(tmp)/'audio.wav'; source.touch()
            args = module.parser().parse_args([str(source)])
            self.assertEqual([fmt for _, fmt in module.plan_outputs(args)[0][1]], ['srt'])
            args.format = 'all'
            self.assertEqual([fmt for _, fmt in module.plan_outputs(args)[0][1]], ['txt', 'srt', 'vtt', 'json'])

    def test_vtt_and_json_unicode_timestamps_and_metadata(self):
        segments = [SimpleNamespace(start=59.9996, end=61.25, text='  你好 <世界> & hello  ')]
        with tempfile.TemporaryDirectory() as tmp:
            vtt = Path(tmp)/'out.vtt'
            module.write_result(vtt, segments, 'vtt')
            self.assertEqual(vtt.read_text(), 'WEBVTT\n\n1\n00:01:00.000 --> 00:01:01.250\n你好 &lt;世界&gt; &amp; hello\n\n')
            output = Path(tmp)/'out.json'
            module.write_result(output, segments, 'json', metadata={'source':'中文.mp4', 'language':'zh', 'duration':62})
            payload = json.loads(output.read_text())
            self.assertEqual(payload['language'], 'zh')
            self.assertEqual(payload['source'], '中文.mp4')
            self.assertEqual(payload['duration'], 62)
            self.assertEqual(payload['text'], '你好 <世界> & hello')
            self.assertEqual(payload['segments'], [{'id':1, 'start':59.9996, 'end':61.25, 'text':'你好 <世界> & hello'}])
            self.assertIn('你好', output.read_text())

    def test_empty_vtt_and_json_are_valid(self):
        with tempfile.TemporaryDirectory() as tmp:
            vtt, output = Path(tmp)/'empty.vtt', Path(tmp)/'empty.json'
            module.write_result(vtt, [], 'vtt')
            module.write_result(output, [], 'json')
            self.assertEqual(vtt.read_text(), 'WEBVTT\n\n')
            self.assertEqual(json.loads(output.read_text()), {'text':'', 'segments':[]})

    def test_time_and_numeric_validation(self):
        self.assertEqual(module.parse_time('01:02:03.5'), 3723.5)
        self.assertEqual(module.parse_time('2:03'), 123)
        for value in ['nan', 'inf', '-1', '00:60:00', '1:2:3:4']:
            with self.assertRaises(module.argparse.ArgumentTypeError): module.parse_time(value)
        for value in ['0', '-1', '1.5']:
            with self.assertRaises(module.argparse.ArgumentTypeError): module.positive_int(value)
        args = module.parser().parse_args(['missing.wav', '--start', '10', '--end', '5'])
        with self.assertRaisesRegex(ValueError, '--end'): module.plan_outputs(args)

    def test_crop_before_recognition_and_restore_word_offsets(self):
        args = module.parser().parse_args(['sample.wav', '--start', '1', '--end', '2', '--quiet'])
        def decoder(source, sampling_rate):
            self.assertEqual(sampling_rate, 16000)
            return list(range(48000))
        audio, offset, duration, end = module.prepare_audio(Path('sample.wav'), args, decoder)
        self.assertEqual((len(audio), audio[0], offset, duration, end), (16000, 16000, 1, 3, 2))
        word = SimpleNamespace(start=0.2, end=0.4, word='hello', probability=0.9)
        segment = SimpleNamespace(start=0, end=1, text='hello', words=[word])
        result = module.collect_segments(iter([segment]), offset, args, 1)
        self.assertEqual((result[0].start, result[0].end), (1, 2))
        self.assertEqual((word.start, word.end), (1.2, 1.4))
        args.start = 4
        with self.assertRaises(ValueError): module.prepare_audio(Path('sample.wav'), args, decoder)

    def test_recursive_preserves_paths_filters_and_excludes_output(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)/'inputs'; root.mkdir()
            output = root/'results'; output.mkdir()
            for sub in ['a', 'b']:
                (root/sub).mkdir(); (root/sub/'same.MP4').touch()
            (root/'notes.txt').touch(); (output/'old.mp4').touch()
            (root/'link.mp4').symlink_to(root/'a/same.MP4')
            args = module.parser().parse_args([str(root), '--recursive', '-o', str(output)])
            plans = module.plan_outputs(args)
            self.assertEqual(len(plans), 2)
            self.assertEqual([str(targets[0][0].relative_to(output.resolve())) for _, targets in plans],
                             ['inputs/a/same.MP4.srt', 'inputs/b/same.MP4.srt'])
            args.recursive = False
            with self.assertRaises(ValueError): module.plan_outputs(args)

    def test_skip_existing_fills_missing_formats_without_loading_model(self):
        with tempfile.TemporaryDirectory() as tmp:
            source = Path(tmp)/'test.wav'; source.touch()
            (Path(tmp)/'test.wav.srt').write_text('keep')
            args = module.parser().parse_args([str(source), '--format', 'all', '--skip-existing', '--quiet'])
            self.assertEqual([fmt for _, fmt in module.plan_outputs(args)[0][1]], ['txt','vtt','json'])
            with patch.object(module, 'select_model', side_effect=AssertionError('must not load')), redirect_stderr(io.StringIO()) as err:
                self.assertEqual(module.main([str(source), '--skip-existing', '--quiet']), 0)
                self.assertEqual(err.getvalue(), '')
            self.assertEqual((Path(tmp)/'test.wav.srt').read_text(), 'keep')
            (Path(tmp)/'test.wav.txt').symlink_to(source)
            with self.assertRaises(ValueError): module.plan_outputs(args)

    def test_wrapping_and_word_timestamps(self):
        words = [SimpleNamespace(start=1, end=1.5, word='你好', probability=0.9),
                 SimpleNamespace(start=1.5, end=2, word='世界', probability=0.8)]
        segments = [SimpleNamespace(start=1, end=2, text='你好世界 hello world', words=words)]
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            module.write_result(root/'wrap.srt', segments, 'srt', max_line_width=4)
            lines = (root/'wrap.srt').read_text().splitlines()[2:]
            self.assertTrue(all(len(line) <= 4 for line in lines))
            module.write_result(root/'word.vtt', segments, 'vtt', word_timestamps=True)
            self.assertEqual((root/'word.vtt').read_text().count(' --> '), 2)
            module.write_result(root/'word.json', segments, 'json', word_timestamps=True)
            payload = json.loads((root/'word.json').read_text())
            self.assertEqual(payload['segments'][0]['words'][1],
                             {'start':1.5,'end':2,'word':'世界','probability':0.8})

    def test_cli_forwards_options_and_quiet_suppresses_progress(self):
        calls = {}
        class FakeModel:
            def __init__(self, model, **kwargs): calls['model'] = kwargs
            def transcribe(self, audio, **kwargs):
                calls['transcribe'] = kwargs
                return iter([SimpleNamespace(start=0, end=1, text='test', words=[])]), SimpleNamespace(language='en', duration=1)
        fake = ModuleType('faster_whisper'); fake.WhisperModel = FakeModel
        onnx = ModuleType('onnxruntime'); onnx.disable_telemetry_events = lambda: None
        with tempfile.TemporaryDirectory() as tmp, patch.dict('sys.modules', {'faster_whisper':fake,'onnxruntime':onnx}), patch.dict('os.environ', {}):
            source = Path(tmp)/'test.wav'; source.touch()
            with redirect_stderr(io.StringIO()) as err, redirect_stdout(io.StringIO()) as out:
                code = module.main([str(source), '--model','small','--quiet','--no-vad','--threads','2',
                                    '--initial-prompt','special term','--word-timestamps'])
            self.assertEqual(code, 0)
            self.assertEqual(err.getvalue(), '')
            self.assertIn('test.wav.srt', out.getvalue())
            self.assertEqual(calls['model']['cpu_threads'], 2)
            self.assertEqual(calls['transcribe']['initial_prompt'], 'special term')
            self.assertTrue(calls['transcribe']['word_timestamps'])
            self.assertFalse(calls['transcribe']['vad_filter'])
            self.assertEqual(sorted(p.name for p in Path(tmp).iterdir()), ['test.wav','test.wav.srt'])

    def test_timestamps(self):
        self.assertEqual(module.timestamp(59.9996), '00:01:00,000')
        self.assertEqual(module.timestamp(3601.25), '01:00:01,250')

    def test_failed_generator_preserves_output(self):
        with tempfile.TemporaryDirectory() as tmp:
            p = Path(tmp)/'result.txt'
            p.write_text('old')
            def broken():
                yield SimpleNamespace(text='new')
                raise RuntimeError('decoding failed')
            with self.assertRaises(RuntimeError):
                module.write_result(p, broken(), 'txt', True)
            self.assertEqual(p.read_text(), 'old')
            self.assertEqual(list(Path(tmp).iterdir()), [p])

    def test_no_overwrite_and_collisions(self):
        with tempfile.TemporaryDirectory() as tmp:
            source = Path(tmp)/'录音.mp4'; source.touch()
            output = Path(tmp)/'录音.mp4.srt'; output.write_text('keep')
            with self.assertRaises(ValueError):
                module.plan_outputs(module.parser().parse_args([str(source)]))
            with self.assertRaises(ValueError):
                module.plan_outputs(module.parser().parse_args([str(source), str(source), '--overwrite']))
            with self.assertRaises(ValueError):
                module.plan_outputs(module.parser().parse_args([str(source), str(output), '--overwrite']))

    def test_batch_continues_after_invalid_media_and_stays_local(self):
        calls = []
        class FakeModel:
            def __init__(self, model, **kwargs):
                calls.append(kwargs)
            def transcribe(self, path, **kwargs):
                if Path(path).name == 'bad.mp4':
                    raise ValueError('no audio stream')
                return iter([SimpleNamespace(start=0, end=1.5, text='你好世界')]), SimpleNamespace(language='zh')
        fake = ModuleType('faster_whisper'); fake.WhisperModel = FakeModel
        onnx = ModuleType('onnxruntime'); onnx.disable_telemetry_events = lambda: calls.append('telemetry-disabled')
        with tempfile.TemporaryDirectory() as tmp, patch.dict('sys.modules', {'faster_whisper':fake, 'onnxruntime':onnx}), patch.dict('os.environ', {}):
            sources = [Path(tmp)/n for n in ['bad.mp4','中文 audio.wav']]
            for p in sources:p.touch()
            self.assertEqual(module.main([str(p) for p in sources] + ['--model', 'small', '--format', 'all']), 1)
            self.assertEqual(calls[0], 'telemetry-disabled')
            self.assertTrue(calls[1]['local_files_only'])
            self.assertEqual((Path(tmp)/'中文 audio.wav.txt').read_text(), '你好世界\n')
            self.assertIn('00:00:00,000 --> 00:00:01,500', (Path(tmp)/'中文 audio.wav.srt').read_text())
            self.assertEqual(json.loads((Path(tmp)/'中文 audio.wav.json').read_text())['language'], 'zh')
            self.assertTrue((Path(tmp)/'中文 audio.wav.vtt').read_text().startswith('WEBVTT\n'))
            self.assertFalse((Path(tmp)/'bad.mp4.txt').exists())


if __name__ == '__main__':
    unittest.main()
