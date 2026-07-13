# RADAR — Road Assessment and Damage Accountability Reporter

An AI-powered mobile application that detects road damage in real time, maps hazardous zones across the city, and alerts drivers before they encounter road hazards.

## Problem Statement

Seven people die on Nepal's roads every day. Road accidents kill five times more Nepalis than all natural disasters combined. Around 60% of Nepal's national road network is classified as poor or fair condition, and poor road conditions contribute significantly to motorcycle accidents.

RADAR addresses three major gaps:
a
- **No data** — Road damage is not systematically mapped.
- **No awareness** — Drivers receive no warning before encountering hazards.
- **No visibility** — Authorities lack a public record of road damage.

## Solution

- Real-time on-device AI road damage detection
- GPS-tagged hazard reports
- Live danger map
- Voice and vibration alerts
- Crowdsourced road intelligence

## Repositories

| Repository | Description |
|---|---|
| RADAR | Flutter mobile application |
| https://github.com/manjitpokhrel/road-damage-training | Training pipeline used during development |

## Technology Stack

- Flutter
- YOLOv8n
- TensorFlow Lite
- Supabase
- OpenStreetMap
- flutter_tts
- geolocator

## Model

The deployed model is **YOLOv8n** exported to TensorFlow Lite.

Development was initially inspired by the **road-damage-training** repository, which uses **YOLOv8s**. After experimentation, a Kaggle implementation based on **YOLOv8n** achieved better mAP during our evaluation, so it was selected for deployment because it provided a better balance of accuracy and mobile performance.

## References

- https://github.com/manjitpokhrel/road-damage-training
- https://www.kaggle.com/code/safalnarshing/pothole-detection
- https://docs.ultralytics.com/
- https://www.openstreetmap.org/

## License

MIT License.
