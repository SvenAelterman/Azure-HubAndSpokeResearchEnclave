# Azure-HubAndSpokeResearchEnclave

A Hub-and-Spoke Azure enclave for secure research.

## Purpose

To accelerate the deployment of a hub-and-spoke architecture for building secure research enclaves in Azure.

## Architecture

[Visio Diagram](/docs/architecture/Research%20Enclave%20Hub%20and%20Spoke%20diagrams.vsdx)

## Features

- Optional use of customer-managed keys for encryption at rest.
- Optional peering to a central hub.

### Compliance

The goal of the project is that the templates will deploy resources that are compliant with the following frameworks:

- HIPAA/HITRUST (according to the Azure Commercial built-in initiative)
- NIST 800-171 R2 (according to the Azure Commercial built-in initiative)
- FedRAMP Moderate (according to the Azure Commercial built-in initiative)

Compliance with all the above frameworks is a work-in-progress.

## Alternative research enclave accelerators

- Azure TRE: <https://microsoft.github.io/AzureTRE/>
- Standalone Azure Secure Enclave for Research: <https://github.com/microsoft/Azure-Secure-Enclave-for-Research>
- Mission Landing Zone (MLZ): <https://github.com/Azure/MissionLZ>
