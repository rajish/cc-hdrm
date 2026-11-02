---
title: 'Keep the token efficiency chart up during reloads and show a 7-day trend'
type: 'bugfix'
created: '2026-11-02'
status: 'done'
route: 'one-shot'
---

# Keep the token efficiency chart up during reloads and show a 7-day trend

## Intent

**Problem:** During the 1.7.0 trial the token efficiency chart flickered on every reload, and its trend line was missing from the 7-day view. A 7-point average needs 7 daily points, and a 7-day range holds at most 8.

**Approach:** Keep the current chart up until new data is ready, and use a 3-point average for the trend in the 7-day range only. The user approved both on 2026-11-02. Shift markers stay on the 7-point average.

## Suggested Review Order

**Reload without flicker**

- The loading row now shows only when there is no chart to keep.
  [`TPPSectionView.swift:78`](../../cc-hdrm/Views/TPPSectionView.swift#L78)

- The default model is chosen before loading, so no all-models chart appears first.
  [`TPPSectionView.swift:290`](../../cc-hdrm/Views/TPPSectionView.swift#L290)

- The chart keeps the range its data was loaded for during a reload.
  [`TPPSectionView.swift:108`](../../cc-hdrm/Views/TPPSectionView.swift#L108)

**7-day trend**

- Only the 7-day range uses the shorter average.
  [`TPPChartDataService.swift:76`](../../cc-hdrm/Services/TPPChartDataService.swift#L76)

- Shift markers stay on the 7-point average.
  [`TPPChartDataService.swift:79`](../../cc-hdrm/Services/TPPChartDataService.swift#L79)

**Tests**

- Covers the 3-point line, the 7-point rule elsewhere and unchanged shift markers.
  [`TPPChartDataServiceTests.swift:359`](../../cc-hdrmTests/Services/TPPChartDataServiceTests.swift#L359)
