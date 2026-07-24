# ITM_SWMM

Fork of artuleon/ITM_SWMM (Dr. Arturo S. Leon), integrating the Illinois Transient Model (ITM) into EPA SWMM as an optional routing engine for transient flow analysis in sewer systems

## About ITM_SWMM

ITM_SWMM combines the EPA Storm Water Management Model (SWMM) with the Illinois Transient Model, a finite-volume, shock-capturing routing method built to represent rapidly filling and draining pipe systems

This extends standard SWMM routing to problems where transient effects such as surcharge, mixed free-surface and pressurized flow, and rapid gate or valve operation matter, for example deep tunnel and interceptor systems

The codebase is written in Pascal, organized into src for model source code, bin for build and runtime artifacts, help for reference documentation, and tests for example and test cases

## Provenance

This repository is a fork of artuleon/ITM_SWMM, maintained by Arturo S. Leon. Upstream source: https://github.com/artuleon/ITM_SWMM

All credit for the ITM_SWMM model and codebase belongs to the original author; see the upstream repository for the latest updates and background on the Illinois Transient Model

## License

Released under the MIT License (see LICENSE)
