# My Hilo: Local Blood Pressure Monitor

An advanced iOS application designed to connect with BLE-based health peripherals (such as the Aktiia pod) and compute Blood Pressure (BP) offline using an embedded AI linear regression model.

## Features

- **Offline Artificial Intelligence**: Computes systolic and diastolic blood pressure locally on-device without needing a backend server connection. Features a carefully tuned linear regression model.
- **BLE Peripheral Integration**: Discovers and connects securely to BLE devices that transmit 244-byte raw PPG waveform characteristics.
- **Computation Steps Visualization**: Breaks down the algorithmic pipeline so researchers and users understand how the BP was calculated. Visualizations include:
  - Raw Waveform Plotting
  - Preprocessing (DC Bias Removal, Normalization, Bandpass filtering)
  - Peak Detection with adaptive thresholding
  - Feature Extraction (Beat morphology features: Amplitude, Rise Time, Decay Time)
  - Quality Filtering (Rejecting beats that do not meet physiological constraints)
  - Aggregation logic
- **Persistent History (SwiftData)**: Effectively manages users' historic blood pressure readings.
- **Overview & Statistics**: A comprehensive Overview Tab displaying Average Systolic/Diastolic BP, Heart Rate, and categorizations using standard classifications (Normal, Elevated, Hypertension Stage 1 & 2).
- **Measurement Deep-Dive**: Offers an expanded view for each measurement mapping out individual logs, exported arrays, and physiological context.
- **MATLAB Export Supported**: Easily export the raw waveform of any sequence to a `.m` MATLAB script for immediate graphing or deeper array analysis.

## Pipeline Architecture

The local AI inference receives PPG payload streams over Bluetooth, decoding the packets natively with Swift.
It identifies "sys-peaks" and formulates features such as:

- `hr_bpm`
- `amplitude`, `auc`
- `rise_time_s`, `decay_time_s`
- `width50_s`
- `upstroke_slope`, `downstroke_slope`
- `notch_delay_s`

These aggregated values define a prediction vector executed against an embedded parameter set (`research_baseline_v1`).

## Disclaimer

**Research-Only.** The measurements provided by this application are estimations intended for research, demonstration, and conceptual purposes. They are NOT medical-grade and shouldn't be utilized for critical clinical decisions or diagnosis.
