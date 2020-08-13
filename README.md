# COVID Trace

COVID Trace is a mobile app that use the Google/Apple Exposure Notification APIs to alert users to potential COVID-19 exposures.

Main features:

- Integrates with the reference [Google Exposure Notification Server](https://github.com/google/exposure-notifications-server)
- Has support for verifying positive COVID-19 diagnosis from authorized health authorities.
- Is easily customizable for the specific needs of local governments and health organizations.

<a href="https://www.figma.com/proto/dZ26JcuOaKsLCMzz3KEnKH/COVID-Trace-App?node-id=1%3A8&scaling=scale-down">![Screenshot of Mobile App](https://covidtrace.com/static/024f965cd42333a3ba7f2354abe8eb18/78ef2/preview.png)</a>

## Local Setup

The app is build on the Flutter framework for both iOS and Android. Follow the local development setup guide here:
https://flutter.dev/docs/get-started/install

The app relies on a combination of local and remote JSON configuration. Be sure to edit `assets/config.json` to specify your remote configuration URL. Here's the minimum remote configuration you must specify:

```json
{
  "exposurePublishUrl": "http://localhost:8080",
  "exposureKeysPublishedBucket": "covidtrace-exposure-keys-published",
  "exposureKeysPublishedIndexFile": "exposure-keys/index.txt",
  "exposureNotificationConfiguration": {
    "minimumRiskScore": 0,
    "attenuationLevelValues": [1, 2, 3, 4, 5, 6, 7, 8],
    "attenuationWeight": 50,
    "daysSinceLastExposureLevelValues": [1, 2, 3, 4, 5, 6, 7, 8],
    "daysSinceLastExposureWeight": 50,
    "durationLevelValues": [1, 2, 3, 4, 5, 6, 7, 8],
    "durationWeight": 50,
    "transmissionRiskLevelValues": [1, 2, 3, 4, 5, 6, 7, 8],
    "transmissionRiskWeight": 50
  }
}
```

In particular you should update `exposurePublishUrl` to point to your server for reporting expsoure keys. For local development, you can specify a path in the `/assets` directory to a "remote" configuration.

## Troubleshooting

- **Issue:** Flutter build fails for iOS after building and running via Xcode.

  **Fix:** `rm -rf ios/Flutter/App.framework`

* **Issue:** Flutter Android build get stuck trying to install debug .apk on to a device.

  **Fix:** `/Path/to/adb uninstall com.covidtrace.app` On MacOS the `adb` tool is typically located at `~/Library/Android/sdk/platform-tools/adb`

  Make sure that you can run `fluttter devices` successfully afterwards. If that hangs kill any running `adb` processes.
