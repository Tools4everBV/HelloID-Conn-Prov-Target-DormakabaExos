# HelloID-Conn-Prov-Target-DormakabaExos

> [!IMPORTANT]
> This repository contains the connector and configuration code only. The implementer is responsible to acquire the connection details such as username, password, certificate, etc. You might even need to sign a contract or agreement with the supplier before implementing this connector. Please contact the client's application manager to coordinate the connector requirements.

<p align="center">
  <img src="">
</p>

## Table of contents

- [HelloID-Conn-Prov-Target-DormakabaExos](#helloid-conn-prov-target-connectorname)
  - [Table of contents](#table-of-contents)
  - [Introduction](#introduction)
  - [Getting started](#getting-started)
    - [Provisioning PowerShell V2 connector](#provisioning-powershell-v2-connector)
      - [Correlation configuration](#correlation-configuration)
      - [Field mapping](#field-mapping)
    - [Connection settings](#connection-settings)
    - [Prerequisites](#prerequisites)
    - [Remarks](#remarks)
  - [Setup the connector](#setup-the-connector)
  - [Getting help](#getting-help)
  - [HelloID docs](#helloid-docs)

## Introduction

_HelloID-Conn-Prov-Target-DormakabaExos_ is a _target_ connector. _DormakabaExos_ provides a set of REST API's that allow you to programmatically interact with its data. The HelloID connector uses the API endpoints listed in the table below.

| Endpoint | Description |
| -------- | ----------- |
| /ExosApi/api/v1.0/persons        |  get endpoint for the account  |
| /ExosApi/api/v1.0/persons/create | post endpoint for the account creation   |
| /ExosApi/api/v1.0/persons{personid}/update | post endpoint for the account update   |
| /ExosApi/api/v1.0/persons{personid}/block | post endpoint for the account update   |
| /ExosApi/api/v1.0/persons{personid}/unblock | post endpoint for the account update   |

The following lifecycle actions are available:

| Action                                  | Description                               |
| --------------------------------------- | ----------------------------------------- |
| create.ps1                              | PowerShell _create_ lifecycle action      |
| disable.ps1                             | PowerShell _disable_ lifecycle action     |
| enable.ps1                              | PowerShell _enable_ lifecycle action      |
| update.ps1                              | PowerShell _update_ lifecycle action      |

| Connection configuration and field mapping files
| configuration.json                      | Default _configuration.json_              |
| fieldMapping.json                       | Default _fieldMapping.json_               |


There is no delete lifecycle action available

## Getting started

### Provisioning PowerShell V2 connector

#### Correlation configuration

The correlation configuration is used to specify which properties will be used to match an existing account within _DormakabaExos_ to a person in _HelloID_.

To properly setup the correlation:

1. Open the `Correlation` tab.

2. Specify the following configuration:

    | Setting                   | Value                             |
    | ------------------------- | --------------------------------- |
    | Enable correlation        | `True`                            |
    | Person correlation field  | `PersonContext.Person.ExternalId` |

Correlation is done based on the: **PersonalNumber**  field in the PersonBaseData object of the person in

> [!TIP]
> _For more information on correlation, please refer to our correlation [documentation](https://docs.helloid.com/en/provisioning/target-systems/powershell-v2-target-systems/correlation.html) pages_.

#### Field mapping

The field mapping can be imported by using the _fieldMapping.json_ file.

### Connection settings

The following settings are required to connect to the API.

| Setting  | Description                        | Mandatory |
| -------- | ---------------------------------- | --------- |
| UserName | The UserName to connect to the API | Yes       |
| Password | The Password to connect to the API | Yes       |
| BaseUrl  | The URL to the API                 | Yes       |


- Make sure to limit the Concurrent Actions to one. Required because there is a maximum number of simultaneous login sessions.
- Run on a local agent server with access to the Application Server.

### Prerequisites
 -HelloID Agent installed with access to the application server.

### Remarks

- The webservice does not support creating disabled accounts. An additional web call is required to disable/block the created accounts. The created accounts are disabled afterward. The accounts that are correlated will not be disabled. (This can be changed of course)

## Setup the connector

> _How to setup the connector in HelloID._ Are special settings required. Like the _primary manager_ settings for a source connector.

## Getting help

> [!TIP]
> _For more information on how to configure a HelloID PowerShell connector, please refer to our [documentation](https://docs.helloid.com/en/provisioning/target-systems/powershell-v2-target-systems.html) pages_.

> [!TIP]
>  _If you need help, feel free to ask questions on our [forum](https://forum.helloid.com)_.

## HelloID docs

The official HelloID documentation can be found at: https://docs.helloid.com/
