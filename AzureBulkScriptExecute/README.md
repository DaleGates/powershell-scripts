# AzureBulkScriptExecute

## Overview

Azure does not provide the functionality to execute the "Run command" in bulk through the azure portal.
This can prove troublesome if adhoc scripts need to be executed on multiple machines as it can be time consuming individually searching for each machine and then going to run command > wait for output.
Leveraging powershells parallel execution functionality we can use the `Invoke-AzVMRunCommand`with an input vm list to execute the commands and output to a corresponding run folder, also handling errors and any VM's that are not found
Throttle limit is currently set to 5 (meaning no more than 5 VM's will be handled at once) this could be set higher but you may hit Api rate limits on azure

## Files

### **AzureBulkScriptInput.txt**

This is for the list of target vm's to search and execute from - they can be windows or linux
Each VM should be seperated by a new line

This should be the Azure VM portal name

#### **Example**

```
VirtalMachine-win
VirtualMachine-Linux
..
```

### **AzureBulkScript.sh**

Linux bash script to execute against linux machines

*NOTE - Ensure this is correct and does not have remnants from a previous run*

### **AzureBulkScript.ps1**

Powershell script to execute against windows machines

*NOTE - Ensure this is correct and does not have remnants from a previous run*

### **AzureBulkScriptExecuteMain.ps1**

The main script to execute in order to use, this will use all of the above files relative to where the script is ran (keep them together in the same folder)

Script will also detect what OS the VM is using and execute either powershell for Windows or Shell for Linux

After running output will be displayed to console as well as corresponding output folders (seperated by date and OS)

Error logs and Not found folders also generated if applicable (if these are not output then there are no errors / missing vm's)

#### **Example**

```
Normal usage
"C:\Path\to\script\AzureBulkScriptExecuteMain.ps1"

The following hosts will be affected:
vm1 vm2
Is this correct? [y/n]: y
VM: vm1 has been found by Azure Name
VM: vm2 has been found by Azure Name
Output for : vm1
[stdout]
"this is a test"
[stderr]



```

```
Debug mode
"C:\Path\to\script\AzureBulkScriptExecuteMain.ps1" -Debug
DEBUG: ON
The following hosts will be affected:
vm1 vm2 vm3
Is this correct? [y/n]: y
DEBUG: Selecting Subscription: Sub1 for vm1
DEBUG: Selecting Subscription: Sub1 for vm2
DEBUG: Selecting Subscription: Sub1 for vm3
DEBUG: Selecting Subscription: Sub2 for vm1
DEBUG: Selecting Subscription: Sub2 for vm2
VM: vm3 has been found by Azure Name
DEBUG: Error on VM1 : The operation requires the VM to be running (or set to run).
Output for : vm3
Enable succeeded: 
[stdout]
"This is a test"

[stderr]

```