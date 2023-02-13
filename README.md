# Azure-HubAndSpokeResearchEnclave

A Hub-and-Spoke Azure enclave for secure research.

## Purpose

To accelerate the deployment of a hub-and-spoke architecture for building secure research enclaves in Azure.

## Architecture

[Visio Diagram](/docs/architecture/Research%20Enclave%20Hub%20and%20Spoke%20diagrams.vsdx)

## Features

- Optional use of customer-managed keys for encryption at rest (required for FedRAMP Moderate compliance).
- Optional peering to a central hub.
- Choice between Active Directory or Azure Active Directory for device authentication and management. Optionally, use Intune for device management with AAD.

### Compliance

The goal of the project is that the templates will deploy resources that are compliant with the following frameworks (according to the Azure Commercial built-in initiatives):

- HIPAA/HITRUST
- NIST 800-171 R2
- FedRAMP Moderate

Compliance with all the above frameworks is a work-in-progress.

## Alternative research enclave accelerators

- Azure TRE: <https://microsoft.github.io/AzureTRE/>
- Standalone Azure Secure Enclave for Research: <https://github.com/microsoft/Azure-Secure-Enclave-for-Research>
- Mission Landing Zone (MLZ): <https://github.com/Azure/MissionLZ>
