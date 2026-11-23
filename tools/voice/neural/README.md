# Нейроозвучка радиоэфира

Прежняя озвучка (Piper `ru-irinia-medium`, `tools/voice/generate_voice.py`) звучала роботизированно.
Теперь реплики синтезирует **Chatterbox Multilingual** (Resemble AI, лицензия MIT, работает офлайн на CPU),
голоса берутся из коротких образцов чтецов **LibriVox** (общественное достояние), ударения ставятся по
словарю **Vosk-TTS ru 0.9** (Apache 2.0).

```bash
python3 -m venv venv && . venv/bin/activate
pip install torch torchaudio --index-url https://download.pytorch.org/whl/cpu
pip install chatterbox-tts vosk-tts faster-whisper num2words scipy soundfile
python -c "from vosk_tts import Model; Model(model_name='vosk-model-tts-ru-0.9-multi')"  # словарь ударений
python make_refs.py                                   # образцы голосов (уже лежат в ref/)
python generate.py ../lines.json /tmp/voice_raw       # «сухие» реплики, проверка разборчивости
python generate.py ../extra_lines.json /tmp/voice_raw # радио демо «Первая смена»
python process_voice.py /tmp/voice_raw                # хоррор-обработка → assets/audio/voice/*.ogg
```

Тексты не менялись: `tools/voice/lines.json` (выгрузка `dump_lines.gd`) и `extra_lines.json`.
В аудио Chatterbox встроен неслышимый водяной знак Perth — так устроена модель, на звук не влияет.
