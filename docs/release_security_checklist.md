# Release Security Checklist

Before producing a release APK/AAB:

- [ ] Confirm `lib/config/local_dev_config.dart` is ignored by git and is not committed.
- [ ] Confirm the release build does not use local development values.
- [ ] Remove any real `DATA4LIBRARY_AUTH_KEY` value from `.env` before release.
- [ ] Confirm `.env` is not listed under Flutter assets in `pubspec.yaml`.
- [ ] Check git tracking status for local secrets:
  - `git status --short lib/config/local_dev_config.dart .env`
  - `git ls-files lib/config/local_dev_config.dart .env`
- [ ] Inspect the final APK/AAB for the Data4Library key string before distribution.
- [ ] Confirm Railway-only secrets exist only on Railway:
  - `ALADIN_TTB_KEY`
  - `DATABASE_URL`
  - `ADMIN_SYNC_KEY`
- [ ] Consider rotating or reissuing the Data4Library key before public release.
- [ ] Confirm Flutter release builds do not pass `--dart-define=DATA4LIBRARY_AUTH_KEY=...`.
- [ ] Confirm `PURCHASE_API_BASE_URL` is public and safe to include if used in release.
