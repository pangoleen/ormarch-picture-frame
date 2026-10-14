# Voice typing with a local model

The frame can turn speech into text with a model that runs on the frame itself. It types the text into
the window that has the focus. The tested frame has no microphone, so the sound comes from another
device on the USB link. Only audio goes over the link.

## Use it

On the frame (one time): `port/frame/stt/install.sh`. It installs `sherpa-onnx` from a ready package,
downloads Moonshine v2 tiny (30 MB) and starts two user services.

On the Mac:

```sh
python3 scripts/mac-dictate.py
```

Press Enter and talk. Make a short pause between sentences: each pause sends that sentence to the
model. Press Enter again to stop.

## Models

| Command on the frame | Model | Speed on the frame | Notes |
| --- | --- | --- | --- |
| `pf-dictate-model quantized` | Moonshine v2 tiny (default) | 0.7 s of work for each second of speech | Fastest. Capitals and punctuation. |
| `pf-dictate-model tiny-en-int8` | Moonshine v1 tiny | 0.9 s | Install with `install.sh moonshine1`. |
| `pf-dictate-model parakeet` | NVIDIA Parakeet 110M | 1.1 s | Install with `install.sh parakeet`. No full stop at the end of a sentence. |

The numbers are from 30 synthetic test sentences on the frame (`docs/experiments.md`, E068). The
streaming Zipformer model that types while you talk made too many errors and is not offered.

## Limits

- English only with these models.
- Speech with no pause for 8 seconds is cut at the quietest point near 8 seconds.
- The sound source is the Mac for now. A microphone on the frame needs hardware (`docs/hardware.md`).
- The service listens only on the USB link address (`10.55.0.1:5055`), not on Wi-Fi.
