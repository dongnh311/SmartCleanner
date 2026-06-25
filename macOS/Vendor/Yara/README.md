# Yara (vendored)

[libyara 4.5.2](https://github.com/VirusTotal/yara) (BSD-3-Clause, see `LICENSE`)
vendored as a self-contained SwiftPM C target — **no** OpenSSL / libmagic /
jansson. The `hash` module uses macOS **CommonCrypto**; `pe` / `dotnet` /
`magic` / `cuckoo` / `dex` / `elf` modules are excluded (Windows/.NET-centric,
or need external libs / the bundled tlsh). Modules compiled: `hash`, `macho`,
`math`, `time`, `console`, `string`.

`Sources/Yara/Yara.swift` is the Swift wrapper (`YaraEngine`); `cyara_shim.c`
exposes `YR_RULE.identifier` so Swift avoids YARA's anonymous-union fields.

To bump: re-vendor `libyara/*.c`, `libyara/include/`, `libyara/proc/mach.c`,
selected `libyara/modules/<m>/`, keep the custom `Sources/CYara/modules/module_list`.
