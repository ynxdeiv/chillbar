# Third-party notices

Chillbar is licensed under the Apache License 2.0 (see `LICENSE`). Parts of it were
ported from, or verified against, the open-source projects below. Their licenses
require the following notices.

## tinytuya — Tuya local protocol

Chillbar's Tuya 3.3 message format, encryption and network discovery
(`Sources/ACTuya/TuyaLocalProtocol.swift`, `TuyaLocalConnection.swift`) are a Swift port
based on [tinytuya](https://github.com/jasonacox/tinytuya). The test vectors in
`Tests/ACTuyaTests` were generated with tinytuya using fake keys.

```
MIT License

Copyright (c) 2024 Jason Cox

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## tuya-device-sharing-sdk — Smart Life QR login

The QR-code login and request encryption (`Sources/ACTuya/TuyaSharingClient.swift`,
`TuyaSharingCrypto.swift`) are a Swift port of Tuya's official
[tuya-device-sharing-sdk](https://github.com/tuya/tuya-device-sharing-sdk).

```
MIT License

Copyright (c) 2023 Tuya

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## Community knowledge

- The data-point layout of AUX-made Tuya air conditioners was cross-checked with the
  device definitions of [tuya-local](https://github.com/make-all/tuya-local) (MIT).
- The QR login uses the public device-sharing registration of
  [Home Assistant](https://www.home-assistant.io/integrations/tuya/), the same way other
  open-source tools do. See the README for what this means.
