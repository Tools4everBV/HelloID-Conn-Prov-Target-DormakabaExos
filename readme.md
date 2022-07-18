# HelloID-Conn-Prov-Target-DormakabaExos

| :information_source: Information |
|:---------------------------|
| This repository contains the connector and configuration code only. The implementer is responsible to acquire the connection details such as username, password, certificate, etc. You might even need to sign a contract or agreement with the supplier before implementing this connector. Please contact the client's application manager to coordinate the connector requirements. |

<p align="center">
  <img src="https://www.dormakaba.com/resource/crblob/2022/310454c471ac3ca193e96a6d44f7cf30/tim-dormakaba-logo-data.gif" width="300">
</p>

## Table of contents

- [Introduction](#Introduction)
- [Getting started](#Getting-started)
  + [Connection settings](#Connection-settings)
  + [Prerequisites](#Prerequisites)
  + [Remarks](#Remarks)
- [Setup the connector](@Setup-The-Connector)
- [Getting help](#Getting-help)
- [HelloID Docs](#HelloID-docs)

## Introduction

_HelloID-Conn-Prov-Target-DormakabaExos_ is a _target_ connector. DormakabaExos provides a set of REST API's that allow you to programmatically interact with it's data. The connector manages Account Management. Authorization Management is out of scope.

## Getting started

### Connection settings

The following settings are required to connect to the API.

| Setting      | Description                        | Mandatory   |
| ------------ | -----------                        | ----------- |
| UserName     | The UserName to connect to the API | Yes         |
| Password     | The Password to connect to the API | Yes         |
| BaseUrl      | The URL to the API                 | Yes         |


### Configuration Settings
- Make sure to set the Concurrent Action limited to one and runs on a local agent server with access to the Application Server. Due to a maximum number of logins.

### Prerequisites
- HelloID Agent installed with access to the application server.

### Remarks
- The webservice does not support creating disabled accounts. An additional web call is required to disable/block the created accounts. The created accounts are disabled afterward. The accounts that are correlated will not be disabled. (This can be changed of course)
- During the development of the connector, I experience an error with the certificate. In order to make the connector work, you must bypass the CertificateCheck. Which you can do as follows in Powershell 5.1:
```PowerShell
# Ignore certificate validation
Add-Type @'
using System.Net;
using System.Security.Cryptography.X509Certificates;
public class TrustAllCertsPolicy : ICertificatePolicy {
    public bool CheckValidationResult(
        ServicePoint srvPoint, X509Certificate certificate,
        WebRequest request, int certificateProblem) {
        return true;
    }
}
'@
[System.Net.ServicePointManager]::CertificatePolicy = [TrustAllCertsPolicy]::new()
```
#### Creation / correlation process
The connector will verify if an account must be either created or correlated. You can change this behavior in the create.ps1 by setting the following boolean value to true: ```$updatePerson = $true. ``` This leads to that the correlated account is updated in the create script.

#### Correlation
Correlation is done based on the: **PersonalNumber**

## Setup the connector

> _How to setup the connector in HelloID._ Are special settings required. Like the _primary manager_ settings for a source connector.

## Getting help

> _For more information on how to configure a HelloID PowerShell connector, please refer to our [documentation](https://docs.helloid.com/hc/en-us/articles/360012558020-Configure-a-custom-PowerShell-target-system) pages_

> _If you need help, feel free to ask questions on our [forum](https://forum.helloid.com)_

## HelloID docs

The official HelloID documentation can be found at: https://docs.helloid.com/
