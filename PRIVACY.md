# Hoop privacy policy

Hoop is a free, open-source companion app for WHOOP straps. This page explains what data Hoop handles
and where it goes.

## What stays on your iPhone

- **Strap data**: heart rate, R-R intervals, motion, temperature and other readings Hoop receives from
  your strap over Bluetooth, and the recovery, strain, sleep and HRV figures it computes from them.
- **What you enter**: your profile (date of birth, sex, height, weight), food log, weigh-ins and goals.
- **Apple Health** data, if you turn on the connection in You > Apple Health. Hoop reads it to compute
  your scores and can write its results back. Health data is never used for advertising.

All of this is stored on your iPhone. Hoop has no account, no server, no analytics and no tracking,
and its developers never receive your data.

## Hoop AI (optional)

Hoop AI is off until you choose **Continue with ChatGPT**. When you use one of its features (the daily
briefing, Ask Hoop, a sleep explanation, or a meal estimate), Hoop sends OpenAI:

- a short summary of the numbers relevant to the request (for example recovery, strain, sleep, vitals,
  recent trends, and your food log for the day), which may include figures derived from Apple Health
  if you enabled it;
- your question, or the meal description or photo you chose.

The request goes directly from your iPhone to OpenAI using your own ChatGPT account and plan. Nothing is
sent in the background, and nothing is sent to Hoop's developers. OpenAI handles these requests under its
own privacy policy and your ChatGPT settings; see <https://openai.com/policies/privacy-policy>.

Your ChatGPT sign-in tokens are stored in the iPhone Keychain. You can disconnect at any time in
You > Hoop AI > Disconnect ChatGPT, and set how much of your plan Hoop may use in your ChatGPT settings.

## Permissions

- **Bluetooth**: only to connect to your strap.
- **Camera**: only when you photograph a meal for Hoop AI to estimate.
- **Apple Health**: only if you turn it on.
- **Notifications**: only for alerts you enable, such as the smart alarm.

## Deleting your data

Deleting Hoop removes everything it stored on your iPhone. To remove Hoop's access to your ChatGPT plan,
disconnect in the app first, or manage connected apps in your ChatGPT settings.

## Contact

Questions or concerns: open an issue at <https://github.com/0xpratzyy/hoop/issues>.

Hoop is not affiliated with, endorsed by, or connected to WHOOP, Inc. or OpenAI.
