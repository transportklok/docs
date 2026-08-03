# Mobile GPS tracker: conceptual implementation plan

Status: concept for investigation

Date: 2026-07-17

## 1. Objective

Use the existing TransportKlok Capacitor application as a phone-based GPS tracker for a vehicle or worker assignment.

The primary goal is to record enough high-quality location data to draw an accurate route later, especially through corners, roundabouts, braking zones, and rapid direction changes.

The tracker should:

- continue collecting location while the app is backgrounded or the screen is locked;
- use accelerometer, gravity, gyroscope, and device-attitude data in addition to GPS;
- increase GPS sampling around turns and other events that affect route geometry;
- reduce sampling while stationary or moving predictably to preserve battery;
- work when the network is unavailable by storing points locally and retrying later;
- send normalized telemetry through the platform and TrackMijn boundaries;
- make the tracking state visible and explicit to the person carrying the phone.

This document describes architecture and behavior. It is not yet an implementation specification with final class names, database migrations, or platform thresholds.

## 2. Feasibility summary

The feature is feasible on both iOS and Android, but the background part must be implemented natively.

Capacitor should provide the JavaScript-to-native control surface, while Swift/Core Location/Core Motion and Kotlin/Android location and sensor APIs perform the continuous work. A normal Vue timer or a JavaScript-only location watcher cannot be treated as a reliable background service because the WebView can be suspended or terminated.

The operating systems provide target intervals rather than an absolute guarantee. The tracker must therefore record timestamps, accuracy, sensor confidence, and delivery delays for every point and must remain useful when updates arrive later than requested.

## 3. Existing workspace foundations

The workspace already contains several useful pieces:

- `mobile/` is a Capacitor 8 application with iOS and Android projects.
- The mobile app already has persistent device authentication and device tokens.
- The mobile app already displays TrackMijn vehicle and person locations on the fleet map.
- Platform contains `TrackMijnVehicleMessageData`, which models timestamp, latitude, longitude, speed, direction, odometer, and related identifiers.
- Platform contains `TrackMijnVehicleMessageIngestService`, which resolves a TrackMijn virtual device and sends normalized messages to TrackMijn.
- TrackMijn accepts messages through the generic virtual-device ingest endpoint.
- The native app configuration currently has only basic Android network permission and an iOS foreground-location description. Background location, motion permissions, foreground services, and the tracking-specific native bridge are not yet implemented.

The design should extend these boundaries instead of sending provider-specific or raw sensor data into TrackMijn.

## 4. Proposed high-level architecture

```text
                    Native mobile tracker
        ┌──────────────────────────────────────────┐
        │ Location service                          │
        │ Accelerometer / gravity / gyroscope      │
        │ Device attitude / sensor fusion           │
        │ Adaptive sampling state machine            │
        │ Rolling sensor and location buffers       │
        │ Offline queue and retry worker             │
        └───────────────────┬──────────────────────┘
                            │ typed Capacitor bridge
                            ▼
                    Mobile Vue application
              start / stop / permission / status UI
                            │ authenticated HTTPS
                            ▼
                    Platform mobile-tracking API
          session validation, routing, deduplication,
          authorization, normalization, audit state
                            │ typed service boundary
                            ▼
                 TrackMijn vehicle message ingest
          virtual device, route processing, map history
```

The native tracker must be able to continue collecting and queueing points even when the Vue application is not active. The Vue layer should be responsible for user interaction, configuration, status, and a live preview—not for the tracking lifecycle itself.

## 5. Identity and routing model

The backend must never trust a client-submitted arbitrary vehicle identifier.

When tracking starts, platform should issue or activate a scoped tracking session containing at least:

- organization;
- authenticated mobile device;
- Worker, when tracking is person-owned;
- vehicle, when tracking is vehicle-owned;
- tracking start time and optional end time;
- sampling profile;
- session status and revocation state;
- a server-generated session identifier;
- a short-lived upload credential or an authenticated session-token flow.

The user-facing model must follow the workspace ownership rule: a Worker is the person, while an Engagement is only the contract wrapper. A phone belonging to a Worker must therefore submit and resolve through Worker-owned relationships. An Engagement must not be used as a worker substitute.

There are three viable product modes:

### 5.1 Phone assigned to a vehicle

The phone acts as a temporary or permanent virtual telemetry device for one vehicle. This fits the existing TrackMijn vehicle message ingest path most directly.

### 5.2 Phone assigned to a Worker

The phone reports the current Worker location. The platform resolves the active vehicle assignment, if one exists, and decides whether to enrich the telemetry with the vehicle relationship.

### 5.3 Phone assigned to a current vehicle assignment

The phone follows the Worker’s active assignment and can change vehicle context as assignments change. This is the most flexible mode but requires careful handling of assignment changes and gaps.

The first proof of concept should use one explicit phone-to-vehicle mapping. The more flexible Worker and assignment modes should follow after the telemetry pipeline is proven.

## 6. Native iOS implementation

### 6.1 Core Location

Implement a native iOS tracking service around `CLLocationManager` or the equivalent current Core Location session APIs.

The service needs to support:

- precise location authorization;
- `Always` authorization for continuous background tracking where required;
- the `location` background mode in the application capabilities and `Info.plist`;
- `allowsBackgroundLocationUpdates = true`;
- a deliberate choice for `pausesLocationUpdatesAutomatically`;
- `desiredAccuracy` changes between power-saving and high-accuracy profiles;
- `distanceFilter` changes between profiles;
- background-location transparency through the blue location indicator.

The existing iOS permission text should be expanded to explain that TransportKlok records location while the app is in the background or the device is locked. Motion permissions also require an `NSMotionUsageDescription` entry.

Apple documents `distanceFilter` as the minimum horizontal movement before an update is generated. It is a useful optimization, but it is not a promise that every movement produces an immediate fix. See [Apple distance filter documentation](https://developer.apple.com/documentation/corelocation/cllocationmanager/distancefilter).

### 6.2 Core Motion

Use `CMMotionManager` and processed `CMDeviceMotion` data where available.

The native service should use:

- `userAcceleration` for acceleration after gravity is separated;
- `gravity` to establish the downward vector and device orientation;
- `rotationRate` for turn-rate detection;
- `attitude` to transform device-axis measurements into a stable world or vehicle frame;
- `CMMotionActivityManager` as an optional high-level activity signal.

Core Motion can distinguish gravity from user acceleration and exposes attitude, rotation, acceleration, and rotation-rate data. See [Apple Core Motion](https://developer.apple.com/documentation/CoreMotion) and [CMDeviceMotion](https://developer.apple.com/documentation/coremotion/cmdevicemotion).

### 6.3 iOS lifecycle behavior

The tracker must be started while the application is visible and authorized. The native service must recreate or restore the required Core Location state after relaunch where the operating system delivers queued events.

The design must not promise uninterrupted execution after every possible user action. For example, force-quitting an app, revoking permissions, enabling restrictive power settings, or losing location availability can interrupt delivery. The app should expose a clear health status when it next becomes active.

## 7. Native Android implementation

### 7.1 Fused location provider

Use `FusedLocationProviderClient` with a `LocationRequest` that can be replaced at runtime.

The request profiles should control:

- priority, including balanced and high accuracy;
- desired interval;
- minimum update interval;
- minimum update distance;
- maximum update delay for batching when accuracy urgency is low;
- whether the request is active only during a tracking session.

Android documents these values as best-effort hints. The device can deliver slower or faster than the requested interval, and the client should use the actual timestamp from each `Location` object. See [Android LocationRequest](https://developers.google.com/android/reference/com/google/android/gms/location/LocationRequest).

### 7.2 Foreground service

Continuous background tracking should run through an Android foreground service with:

- a persistent notification stating that TransportKlok is recording location;
- a declared `location` foreground-service type;
- fine/coarse location permissions;
- background location permission where the selected product behavior requires it;
- handling for Android 10+ background permission flows;
- handling for Android 12+ approximate-location choices;
- explicit battery-optimization and manufacturer-restriction diagnostics.

Android’s foreground service model is important because a foreground service keeps location access available while the screen is off and makes the use visible to the user. See [Android location permissions](https://developer.android.com/develop/sensors-and-location/location/permissions).

The Google Play background-location policy must be evaluated before release. The feature needs to be clearly core to the fleet-tracking product and must be explained in the store listing and in-app permission education.

### 7.3 Android motion sensors

Use `SensorManager` and prefer the following sensors where available:

- `TYPE_LINEAR_ACCELERATION` for acceleration excluding gravity;
- `TYPE_GRAVITY` for the gravity vector;
- `TYPE_GYROSCOPE` for rotation rate;
- `TYPE_ROTATION_VECTOR` for device attitude and orientation fusion;
- `TYPE_ACCELEROMETER` as a fallback;
- activity recognition as an optional high-level signal.

Android distinguishes acceleration including gravity from linear acceleration excluding gravity and exposes rotation around all three axes. See [Android motion sensors](https://developer.android.com/develop/sensors-and-location/sensors/sensors_motion).

Sensor availability and quality vary between devices. The tracker must detect missing sensors and degrade gracefully to GPS-only tracking rather than failing the entire session.

## 8. Force and turn detection

### 8.1 What should be detected

The tracker should detect more than a generic “moving” flag:

- longitudinal acceleration: acceleration and braking;
- lateral acceleration: cornering force;
- vertical acceleration: bumps and road surface events;
- jerk: rapid changes in acceleration;
- yaw rate: rotation around the vertical axis;
- pitch and roll changes: hills, tilting, and mounting changes;
- sustained rotation: a corner or roundabout;
- heading change from GPS: confirmation of the turn;
- speed: context for interpreting the same force at different velocities.

The gyroscope’s yaw rate is usually the earliest and cleanest signal for a vehicle turn. Lateral acceleration helps confirm that the turn is a real vehicle maneuver rather than a phone being rotated by hand.

Gravity is not itself the corner force. It is used to determine the device’s orientation and remove the approximately 9.81 m/s² gravity component from raw accelerometer data.

### 8.2 Coordinate-frame calibration

The phone may be mounted vertically, horizontally, upside down, or at an angle. Therefore the service must not assume that the phone’s X axis equals the vehicle’s lateral axis.

At tracking start:

1. Ask the user to place or mount the phone normally.
2. Capture gravity and attitude for a short calibration window.
3. Establish a phone-to-vehicle transform.
4. Allow a small automatic refinement using the first sustained driving segment and GPS heading.
5. Mark the calibration confidence.

If the phone is removed or remounted, the service should detect a large orientation change and request recalibration or temporarily lower confidence in lateral-force interpretation.

### 8.3 Sensor processing pipeline

Process sensor data natively in this order:

1. Timestamp all sensor samples using a monotonic clock where available.
2. Normalize sensor units and account for sensor axis conventions.
3. Separate gravity from user acceleration.
4. Transform acceleration into vehicle-relative axes.
5. Apply low-pass filtering to estimate sustained force.
6. Apply high-pass or band-pass filtering to detect jerk and short events.
7. Smooth gyroscope yaw rate to reduce noise.
8. Calculate rolling features over windows such as 250 ms, 1 second, and 3 seconds.
9. Calculate confidence from sensor availability, calibration quality, GPS accuracy, and signal consistency.
10. Feed the features into the sampling state machine.

Raw sensor data should normally remain on the device. Upload derived features with selected GPS points for diagnostics and route-quality analysis, not every accelerometer sample.

## 9. Adaptive sampling state machine

The service should use hysteresis so that it does not switch profiles repeatedly because of sensor noise.

### 9.1 Suggested states

#### Idle or stationary

- Low-power location mode.
- Large distance filter.
- GPS target in the range of 2–5 minutes, subject to platform behavior.
- Motion sensors running at a low diagnostic rate or using a low-power activity signal.

#### Moving straight

- Balanced or high-accuracy location mode depending on product requirements.
- GPS target around 2–5 seconds during normal driving.
- Store speed, heading, accuracy, and motion features.

#### Turn suspected

Enter when multiple signals agree, for example:

- yaw rate exceeds a calibrated threshold for a sustained short window;
- lateral acceleration exceeds a speed-aware threshold;
- GPS heading is changing consistently;
- the vehicle is moving above a minimum speed.

Actions:

- switch to high-accuracy GPS;
- reduce the target interval to approximately 0.5–1 second;
- reduce the minimum distance filter;
- preserve the preceding sensor buffer;
- keep the high-rate mode active briefly after the turn signal falls below the exit threshold.

#### High-dynamics event

Use for sharp braking, strong acceleration, large yaw rate, collision-like force, or abrupt orientation change.

Actions may include:

- immediate one-shot current-location request where supported;
- high-rate GPS for a short bounded window;
- storing a richer diagnostic record;
- raising a local event for later review.

This state should not automatically become a safety or crash-detection product feature without a separate safety review.

#### Recovering or uncertain

Use when sensor data and GPS disagree, calibration is poor, or the phone appears to have moved in its mount.

Actions:

- use a medium sampling profile;
- collect more sensor/GPS evidence;
- flag the route segment with lower confidence;
- prompt for recalibration when the user returns to the app.

### 9.2 Thresholds must be calibrated

Do not hard-code one universal “corner force” threshold at the start. The threshold depends on:

- vehicle type;
- phone model and sensor quality;
- phone mounting position;
- speed;
- road surface;
- whether the phone is loose or fixed;
- whether the person is a driver or passenger.

Start with configurable thresholds and log anonymized diagnostic metrics. Use recorded test drives to select values and introduce speed-aware thresholds.

## 10. The rolling buffer and corner accuracy

The rolling buffer is essential because turn detection happens after the physical maneuver has started.

Maintain on-device buffers containing:

- the most recent 1–2 seconds of motion features or selected raw samples;
- the most recent GPS points and their timestamps;
- the active sampling state;
- sensor and GPS confidence.

When a turn is detected:

1. Preserve the preceding buffer as the turn prelude.
2. Switch to high-rate GPS immediately.
3. Continue high-rate GPS until the turn has ended and a short recovery period has elapsed.
4. Upload or queue the complete segment as one logical batch.

This prevents the route from beginning at the first high-rate GPS point and missing the initial bend.

## 11. Sensor fusion and route reconstruction

GPS remains the authoritative geographic position source. IMU data should improve sampling decisions and fill short gaps, not silently fabricate a precise route.

Use the following hierarchy:

1. High-quality GPS fix with good horizontal accuracy.
2. GPS fix corrected or smoothed using recent IMU context.
3. Short dead-reckoning estimate between reliable GPS fixes.
4. No estimate when uncertainty grows beyond a defined limit.

For later route drawing, platform or TrackMijn can apply:

- outlier rejection for impossible jumps;
- speed and acceleration plausibility checks;
- timestamp ordering and duplicate removal;
- smoothing that preserves real corners;
- road-network map matching where appropriate;
- confidence visualization for reconstructed segments.

Avoid over-smoothing. A smooth line that cuts across a roundabout is worse than a slightly noisy line that preserves the actual path.

## 12. Location record contract

The native service should create a typed local location record containing at least:

- client-generated point identifier;
- tracking-session identifier;
- captured timestamp;
- latitude and longitude;
- horizontal accuracy;
- altitude and vertical accuracy when available;
- speed and speed accuracy when available;
- course/heading and course accuracy when available;
- active sampling state;
- motion classification;
- lateral, longitudinal, and vertical acceleration summaries;
- yaw rate summary;
- sensor/calibration confidence;
- device-side sequence number;
- upload status.

The platform-facing DTO should contain the fields needed for authorization, deduplication, normalization, and TrackMijn ingest. Raw sensor samples should not be part of the hot ingest payload.

The existing `TrackMijnVehicleMessageData` can remain the normalized TrackMijn-facing message shape. Derived motion information can be stored as root-level telemetry keys if TrackMijn needs it, or kept in platform-side diagnostics if it is only used to improve route quality.

## 13. Offline storage and upload

The native tracker must never discard a captured point merely because the network is unavailable.

Use a durable local queue with:

- encrypted or OS-protected storage;
- append-only point insertion;
- upload status and retry count;
- exponential backoff with a maximum retry interval;
- batch uploads;
- idempotency based on session ID plus point ID or sequence number;
- retention limits to prevent unlimited storage growth;
- cleanup only after server acknowledgement;
- recovery after app relaunch or device reboot where platform rules permit it.

The server should accept late points and order them by captured timestamp, not upload timestamp.

## 14. Platform communication route

The mobile app should communicate with a dedicated platform endpoint rather than directly calling TrackMijn.

The platform endpoint should:

1. Authenticate the device and tracking session.
2. Validate that the session is active and belongs to the organization.
3. Validate Worker and vehicle ownership or assignment scope.
4. Reject points outside the allowed session window unless explicitly configured for late delivery.
5. Deduplicate points.
6. Validate coordinates, timestamps, accuracy, and impossible speeds.
7. Convert the input DTO into normalized `TrackMijnVehicleMessageData` objects.
8. Enforce vehicle-level telemetry-source exclusivity.
9. Send accepted vehicle messages to TrackMijn through the existing service boundary.
10. Return per-point acceptance/rejection information so the device can delete or retain queue entries correctly.

The endpoint should support batched uploads and partial acceptance. One malformed point must not cause an entire offline batch to be lost.

## 15. Platform and TrackMijn integration model

The phone tracker is an internal mobile telemetry source, but it should still respect the project’s integration concepts.

The conceptual platform responsibilities are:

- manage the mobile tracking session;
- own device-to-worker and device-to-vehicle identity;
- normalize native location data;
- store provider/source metadata in stable, instance-scoped meta where appropriate;
- enforce telemetry-source exclusivity;
- route accepted messages to TrackMijn.

TrackMijn responsibilities are:

- receive generic normalized vehicle messages;
- associate messages with the virtual device and vehicle;
- process trips, stops, and route history;
- expose the resulting route/location data to the existing map flows.

TrackMijn must not know whether a message came from a Teltonika device, a mobile phone, or another vendor-specific source. Vendor- and device-specific interpretation belongs in platform.

If the phone is modeled as a GPS provider integration, use the normal integration instance and capability model. The telemetry capability should represent receiving mobile telemetry; it should not be implemented as a fake pull or sync operation when the phone is pushing data.

## 16. Telemetry ownership and conflicts

A vehicle must have only one active telemetry source.

Before accepting a mobile point, platform must verify that:

- the mobile tracker is authorized for the vehicle;
- no other active telemetry handler owns that vehicle;
- the mobile source has not been revoked or replaced;
- the source ownership window covers the point timestamp.

When a physical GPS device is activated for the same vehicle, the mobile session should be stopped or explicitly transferred. This conflict should be resolved in platform before TrackMijn ingest.

## 17. Capacitor bridge design

Expose a small typed plugin API to Vue, for example conceptually:

- `getCapabilities()`
- `requestPermissions()`
- `startTracking(sessionConfiguration)`
- `stopTracking()`
- `getTrackingStatus()`
- `getQueueStatus()`
- `flushQueue()`
- `addListener('trackingStatusChanged', ...)`
- `addListener('locationCaptured', ...)` for foreground preview only

The exact names should be chosen during implementation after checking existing plugin conventions.

The bridge must not expose raw native lifecycle assumptions to the rest of the Vue application. It should return a common model for iOS and Android and include platform-specific capability flags where behavior differs.

The native layer should remain functional if the JavaScript bridge is unavailable for a period of time.

## 18. Privacy, consent, and user experience

Tracking must be explicit and visible.

The UI should show:

- tracking inactive, starting, active, paused, degraded, offline, or stopped;
- current session owner and vehicle context;
- last captured point time;
- last successfully uploaded point time;
- queue size;
- current sampling profile;
- permission and battery warnings;
- calibration status;
- a clear stop action.

The first release should explain:

- why background location is required;
- when tracking starts and stops;
- what happens without network connectivity;
- how long points are retained;
- who can see the location data;
- how the user can revoke tracking.

The iOS blue location indicator and Android foreground notification should be treated as part of the product design, not as an implementation detail to hide.

## 19. Testing strategy

### 19.1 Native device matrix

Test on real devices, not only simulators:

- recent iPhone with Dynamic Island;
- older supported iPhone;
- recent Android device with Google Play services;
- Android device from a manufacturer with aggressive battery management;
- devices with and without gyroscope;
- devices with approximate location selected;
- device mounted horizontally and vertically.

### 19.2 Lifecycle tests

Test:

- app backgrounded;
- screen locked;
- app resumed;
- app relaunched;
- app force-quit;
- device rebooted;
- permissions revoked;
- location services disabled;
- low-power mode enabled;
- battery saver enabled;
- network lost and restored;
- server unavailable;
- phone remounted during a session.

### 19.3 Driving scenarios

Capture reference drives containing:

- straight highway driving;
- urban stop-and-go traffic;
- sharp left and right turns;
- roundabouts;
- gradual bends;
- braking before turns;
- accelerations after turns;
- speed bumps;
- tunnels and urban GPS multipath;
- stationary idling;
- phone movement by a passenger.

Compare the recorded route with a high-quality reference track. Measure:

- point-to-reference error;
- corner entry and exit error;
- missed turns;
- number of points per turn;
- battery consumption per hour;
- queue recovery time;
- duplicate or out-of-order points;
- false turn detections.

### 19.4 Automated tests

Add tests for:

- sensor feature extraction;
- gravity removal;
- coordinate-frame transformation;
- turn state transitions;
- hysteresis and cooldown behavior;
- point validation and deduplication;
- offline queue retry and acknowledgement;
- partial batch acceptance;
- tracking-session authorization;
- telemetry-source exclusivity;
- normalized TrackMijn message generation.

## 20. Delivery phases

### Phase 1: native feasibility spike

- Add a minimal native Capacitor plugin or evaluate a maintained background-geolocation plugin.
- Collect foreground GPS, accelerometer, gravity, and gyroscope data.
- Display raw sensor diagnostics in a development-only screen.
- Verify iOS background updates and Android foreground-service updates.
- Record real-device traces without backend integration.

### Phase 2: adaptive local tracker

- Add calibration.
- Add coordinate-frame transformation.
- Add rolling sensor buffer.
- Add turn and force feature extraction.
- Add sampling state machine.
- Persist points locally.
- Add battery and sensor-quality diagnostics.

### Phase 3: platform ingestion

- Add scoped tracking sessions.
- Add the authenticated batch upload endpoint.
- Add typed DTOs and validation.
- Add deduplication and partial acknowledgements.
- Route normalized points into the existing TrackMijn ingest service.
- Enforce telemetry-source exclusivity.

### Phase 4: map validation

- Show the phone source on the existing fleet map.
- Compare straight routes and corners against reference recordings.
- Tune thresholds and sampling profiles.
- Add route confidence and diagnostics.

### Phase 5: production hardening

- Complete App Store and Google Play permission disclosures.
- Test battery impact across supported devices.
- Add monitoring for failed uploads and degraded sessions.
- Add retention and privacy controls.
- Roll out to a small pilot group before general release.

## 21. Important design decisions to make before coding

1. Is the first product mode vehicle-owned, Worker-owned, or assignment-owned?
2. Is the phone expected to be fixed in a vehicle mount, or can it be carried freely?
3. What route accuracy is required: normal fleet history, turn reconstruction, or near-navigation quality?
4. What is the maximum acceptable battery consumption per hour?
5. Should raw motion summaries be retained for diagnostics, and for how long?
6. What is the maximum offline queue duration?
7. Which existing TrackMijn virtual-device lifecycle should represent a mobile source?
8. Should mobile telemetry be exclusive for a vehicle or allowed as a fallback source?
9. Which iOS and Android versions and device classes are supported?
10. Will map matching be done in TrackMijn, platform, or a later route-processing service?

## 22. Recommended first implementation profile

For the first driving prototype, use conservative targets rather than trying to maximize precision immediately:

- sensor processing: native, approximately 20–50 Hz;
- normal driving GPS target: 2–5 seconds;
- suspected-turn GPS target: 0.5–1 second;
- minimum movement filter during high-rate mode: approximately 5–10 metres or platform equivalent;
- rolling sensor buffer: 1–2 seconds;
- post-turn high-rate cooldown: approximately 2–5 seconds;
- local queue: encrypted, batched, and acknowledged per point;
- upload: platform only, never direct from the phone to TrackMijn;
- route drawing: use actual GPS points first, then evaluate sensor-assisted interpolation and map matching separately.

These are starting targets for experiments, not guarantees. The final values must come from real-device driving traces and battery measurements.

## 23. Definition of success

The concept is ready for production implementation when a real-device pilot can demonstrate that:

- tracking continues in the background on supported iOS and Android devices;
- the route contains enough points through representative corners and roundabouts;
- false turn detections do not cause unacceptable battery drain;
- offline points are recovered without duplication or loss;
- the backend accepts only authorized device/session/vehicle data;
- TrackMijn receives only normalized generic telemetry;
- a second telemetry source cannot silently overwrite the mobile source;
- the user can clearly see, start, stop, and understand background tracking;
- the measured route quality and battery cost meet the product targets.

