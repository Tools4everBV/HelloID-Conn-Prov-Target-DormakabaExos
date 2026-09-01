# HelloID-Conn-Prov-Target-DormakabaExos

> [!WARNING]
> Version `4.3.3` of DormakabaExos introduces a new method for retrieving the authentication token. This change is implemented in this release. If this method does not work with older installations, please use a previous release or contact DormakabaExos for advice.

> [!IMPORTANT]
> This repository contains the connector and configuration code only. The implementer is responsible to acquire the connection details such as username, password, certificate, etc. You might even need to sign a contract or agreement with the supplier before implementing this connector. Please contact the client's application manager to coordinate the connector requirements.

<p align="center">
  <img src="https://raw.githubusercontent.com/Tools4everBV/HelloID-Conn-Prov-Target-DormakabaExos/refs/heads/main/Logo.png">
</p>

## Table of contents

- [HelloID-Conn-Prov-Target-DormakabaExos](#helloid-conn-prov-target-DormakabaExos)
  - [Table of contents](#table-of-contents)
  - [Introduction](#introduction)
  - [Supported features](#supported-features)
  - [Getting started](#getting-started)
    - [HelloID Icon URL](#helloid-icon-url)
    - [Requirements](#requirements)
    - [Connection settings](#connection-settings)
    - [Correlation configuration](#correlation-configuration)
    - [Field mapping](#field-mapping)
    - [Account Reference](#account-reference)
  - [Remarks](#remarks)
  - [Development resources](#development-resources)
    - [API endpoints](#api-endpoints)
    - [API documentation](#api-documentation)
  - [Getting help](#getting-help)
  - [HelloID docs](#helloid-docs)

## Introduction

_HelloID-Conn-Prov-Target-DormakabaExos_ is a _target_ connector. _DormakabaExos_ provides a set of REST API's that allow you to programmatically interact with its data. 

## Supported  features

The following features are available:

| Feature                 | Supported | Actions  | Remarks   
| ----------------------- | --------- | ---------- | ------------ |
| **Account Lifecycle**   | ✅        | Create, Update, Enable, Disable  |  |
| **Permissions**         | ✅        | Retrieve, Grant, Revoke  | Static  |
| **Resources**           | ❌        | -  |  |
| **Uniqueness**          | ❌        | - |  |
| **Entitlement Import: Accounts**    | ✅ | -  |                                     |
| **Entitlement Import: Permissions** | ✅  |  -  | Only available for AccessRights  |
| **Governance Reconciliation Resolutions** | ❌ | Reconciliation [Governance Remarks](#governance-remarks) | |

## Getting started

### HelloID Icon URL
URL of the icon used for the HelloID Provisioning target system.
```
https://raw.githubusercontent.com/Tools4everBV/HelloID-Conn-Prov-Target-DormakabaExos/refs/heads/main/Icon.png
```

### Requirements
- HelloID Agent installed with access to the application server.

### Connection settings

The following settings are required to connect to the API.

| Setting        | Description                                          | Mandatory |
| -------------- | ---------------------------------------------------- | --------- |
| UserName       | The UserName to connect to the API                   | Yes       |
| Password       | The Password to connect to the API                   | Yes       |
| BaseUrl        | The URL to the API                                   | Yes       |
| TenantId       | Default `0` or `1`. Contact DormakabaExos for advice | Yes       |
| RequestChannel | Default `0`. Contact DormakabaExos for advice        | Yes       |
| BlockBadge     | Default `true`. Contact DormakabaExos for advice     | No        |
| UnassignBadge  | Default `false`. Contact DormakabaExos for advice    | No        |

> [!IMPORTANT]
> - Make sure to limit the Concurrent Actions to **1**. This is **required** because there is a maximum number of simultaneous login sessions.
>- Run on a local agent server with access to the Application Server.

### Correlation configuration

The correlation configuration is used to specify which properties will be used to match an existing account within _DormakabaExos_ to a person in _HelloID_.

To properly setup the correlation:

1. Open the `Correlation` tab.

2. Specify the following configuration:

    | Setting                  | Value                             |
    | ------------------------ | --------------------------------- |
    | Enable correlation       | `True`                            |
    | Person correlation field | `Person.ExternalId`               |
    | Account correlation field | `PersonBaseData.PersonalNumber`  |


> [!TIP]
> _For more information on correlation, please refer to our correlation [documentation](https://docs.helloid.com/en/provisioning/target-systems/powershell-v2-target-systems/correlation.html) pages_.

### Field mapping

The field mapping can be imported by using the _fieldMapping.json_ file.

### Account Reference

The account reference is populated with the property `PersonBaseData.PersonId` property from _DormakabaExos_

## Remarks

- The webservice does not support creating disabled accounts. An additional web call is required to disable/block the created accounts. The created accounts are disabled afterward. The accounts that are correlated will not be disabled. (This can be changed of course)
- There is no delete event implemented. If the account is deleted history is also purged in DormakabaExos

## Development resources

### API endpoints

The HelloID connector uses the API endpoints listed in the table below.

| Endpoint                                    | HTTP Method |      Description                            |
| ------------------------------------------- | -----------|-------------------------------------- |
| /persons                   | GET | endpoint for the account           |
| /persons/create            | POST | endpoint for the account creation |
| /persons{personid}/update  | POST | endpoint for the account update   |
| /persons{personid}/block   | POST | endpoint for the account disable  |
| /persons{personid}/unblock | POST | endpoint for the account enable   |
| /persons{personid}/assignAccessRight | POST | endpoint for assigning accessright   |
| /persons{personid}/unassignAccessRight | POST | endpoint for unassigning accessright |
| /accessRights | GET | endpoint list of accessrights |
| /badges/block | POST | endpoint to block badge |
| /persons{personid}/unassignBadge | POST | endpoint to unassign badge   |

### API documentation
Only available via the local DormakabaExos server. Example url: https://[servername]/exosapi/#!/person/get_v1_0_persons


## Getting help

> [!TIP]
> _For more information on how to configure a HelloID PowerShell connector, please refer to our [documentation](https://docs.helloid.com/en/provisioning/target-systems/powershell-v2-target-systems.html) pages_.

## HelloID docs

The official HelloID documentation can be found at: https://docs.helloid.com/
