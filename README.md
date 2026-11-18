# Health Agent

An iPhone app that reads Apple Health, reminds you to log lunch and dinner, estimates
nutrition with the DeepSeek API, charts the trends with a weight and body-fat forecast, and builds
the weekly health summary on the phone each Sunday.

## Run it on your iPhone

1. Open `HealthAgent.xcodeproj` in Xcode 16 or later.
2. Select the **HealthAgent** target › **Signing & Capabilities**, and choose your Team.
   If the bundle identifier `com.xuyaofeng.HealthAgent` is taken, change it.
   HealthKit should already be listed under capabilities; if not, add it with **+ Capability**.
3. Plug in the iPhone, pick it as the run destination, and press Run.
   HealthKit has almost no data in the Simulator, so use the real phone.
4. On first launch, allow Health access (turn on all categories) and notifications.
5. In the app, open **Settings** and paste a DeepSeek API key (from platform.deepseek.com).

With a free Apple ID the app stops opening after 7 days and needs to be run from Xcode
again; a paid developer account extends that to a year.

## What is where

| Path | What it does |
|---|---|
| `HealthAgent/Services/HealthKitManager.swift` | All Apple Health reads and writes |
| `HealthAgent/Services/DeepSeekClient.swift` | Meal estimate from photos, dish suggestions and weekly observations via the DeepSeek API |
| `HealthAgent/Services/ReminderManager.swift` | Lunch, dinner and Sunday report notifications |
| `HealthAgent/Services/Forecast.swift` | Smoothed trend, straight-line forecast with a range, energy-balance estimate |
| `HealthAgent/Services/WeeklyReport.swift` | The Sunday-to-Saturday summary, week-over-week changes, JSON / Markdown export |
| `HealthAgent/Views/QuickLogView.swift` | Photo-only meal logging: pick a photo, the estimate is saved automatically |
| `HealthAgent/Models/WaterEntry.swift` | Water log with two bottle sizes (500 ml and 1.5 L by default, set in Settings) |
| `HealthAgent/Services/GoalPlan.swift` | Monthly weight goal from a full week of data, daily and per-meal targets |
| `HealthAgent/Views/PlanView.swift` | Goal, targets and dish recommendations |
| `HealthAgent/Views/FoodSummaryImage.swift` | Picture for the weekly email: meal table and nutrition pie chart |
| `HealthAgent/Views/` | Today, Meals, Trends, Weekly and Settings screens, plus the PDF page |

## Weekly report

On Sunday (11:00 by default) a notification arrives; tapping it builds the
summary for the week that just ended, saves a PDF, a JSON data file and a Markdown copy to
**Files › On My iPhone › Health Agent › Weekly summaries**, and opens a ready-to-send
email with the PDF attached. iOS does not let an app send email
without that one tap.

## Notes

- The forecast is a straight line through the last 4 weeks of readings (8 if there are too
  few), with a range that widens further out. It needs at least 4 readings over a week.
- The energy-balance figure uses only days with both lunch and dinner logged, and 7,700 kcal
  per kilogram. Meal estimates from photos are approximate.
- The default model name is `deepseek-flash` (it accepts images); change it in Settings if DeepSeek renames it.
