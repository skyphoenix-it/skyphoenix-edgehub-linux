---
apply: by model decision
instructions: Apply when work affects QML, Qt Quick, UI layout, view models, animations, rendering, scaling, pointer input, gestures, or touchscreen behavior.
---

# Qt/QML Touch UI Requirements

- Keep expensive work and business logic out of QML and the GUI thread.
- Use the existing backend or view-model architecture.
- Avoid binding loops and uncontrolled property-change cascades.
- Avoid timers or animations that run unnecessarily while content is hidden.
- Prefer responsive layouts over absolute coordinates.
- Validate both portrait and landscape layouts.
- Support fractional scaling and different logical resolutions.
- Primary touch targets should normally be at least 48 logical pixels.
- No essential feature may depend only on mouse hover.
- Touch scrolling, dragging, long press, cancellation, and accidental touches
  must behave predictably.
- Provide loading, empty, disconnected, disabled, and error states.
- Animations must be interruptible and must not delay input.
- Respect reduced-motion and accessibility settings where available.
- Avoid excessive blur, continuous shaders, and permanent animations.
- Keyboard and mouse remain supported as fallback input methods.