#It's better if interacting computers are on the same domen. 
#For the situations when they are not, check if your internal switch has a dns server written in it's properties

[CmdletBinding()]
Param(
    [parameter(Mandatory=$false, HelpMessage="Enter new drive for your files:")]
    [string]$drive="E"
)
$ErrorActionPreference = "stop"

  #Adding trusted host for the situation when computers are not in the same domen
$DomSwitch = Read-Host "Are your computers on the same domen? [y/n]"
switch ( $DomSwitch )  {
    y { Write-Host "OK"  }
    n { 
        Enable-PSRemoting -SkipNetworkProfileCheck -Force
        $curr=(get-item WSMan:\localhost\Client\TrustedHosts).value
        Set-Item WSMan:\localhost\Client\TrustedHosts -Value ($curr,"vm1.adatum.com") 
    }
}

  #Creating a new folder for files
Invoke-Command -ScriptBlock {
    try {
        $path = (New-Item -ItemType Directory -Path $($drive+":\") -Name SQLTemp).FullName
    }
    catch { [NotSupportedException]
        Write-Host "Unable to create new folder. The given path's format is not supported. Check if you entered correct drive letter"
    }
}  -ComputerName vm1.adatum.com
   
  #check for existing files with the same name  
Invoke-Command -ScriptBlock {
    try {
    Get-ChildItem -Path $path | foreach-Object {
        if ($_.name -like "tempdb.mdf")  {
            Write-Host "Tempdb.mdf file already exists"
             
                $switch=Read-Host "Do you want to remove file? [y/n]"
                    switch ( $switch )  {
                        y { Remove-Item -Path $($path+"tempdb.mdf")
                        }
                        n { Write-Host "Files will not be removed" }       
                        }
        }

        if ($_.name -like "templog.ldf") {
            Write-Host "Templog.ldf file already exists"
             
                $switch=Read-Host "Do you want to remove file? [y/n]"
                    switch ( $switch )  {
                        y { Remove-Item -Path $($path+"templog.ldf")
                        }
                        n { Write-Host "Files will not be removed" }       
                        }
        }
    }
    }
    catch { 
        [System.Exeption]
        Write-Host "System Error!"
    }
    finally {
        Write-Host "Ready for files movement"
    }
}       -ComputerName vm1.adatum.com


$login = "sa"
$cred = Get-Credential -UserName $login -Message "Enter user password"

#Checking files properties before moving
Invoke-Sqlcmd -ServerInstance vm1.adatum.com -Username $Login -Credential $cred -Query @'
    SELECT name, physical_name,size,max_size,growth  
    FROM sys.master_files  
    WHERE database_id = DB_ID(N'tempdb');
'@ 

  #FreeSpace check
  try {
    Invoke-Command -ScriptBlock {
     $freespace=(Get-WmiObject -Class win32_LogicalDisk | Where-Object{$_.DeviceId -match $Drive}).Freespace
    if ($freespace -le 1GB) {
        Write-host "Not enough memory on choosen disk";
        break
    }
    }       -ComputerName vm1.adatum.com
  }
    catch { [System.Exception]
    Write-Host "Error"
    }
    finally {"Ready for moving"}

 #Moving database files
try {
    Invoke-Sqlcmd -ServerInstance vm1.adatum.com -Username $Login -Credential $cred -Query @'
USE [master]
GO
ALTER DATABASE [tempdb] MODIFY FILE ( NAME = N'tempdev', SIZE = 10240KB , FILEGROWTH = 5120KB, FILENAME = 'E:\SQLTemp\tempdb.mdf' )
GO
ALTER DATABASE [tempdb] MODIFY FILE ( NAME = N'templog', SIZE = 10240KB , FILEGROWTH = 1024KB, FILENAME = 'E:\SQLTemp\templog.ldf' )
GO
'@
}
  catch { [System.SqlPowerShellSqlExecutionException]
        Write-Host "Check your query"
  }

 #Checking files properties after moving
Invoke-Sqlcmd -ServerInstance vm1.adatum.com -Username $Login -Credential $cred -Query @'
SELECT name, physical_name,size,max_size,growth  
FROM sys.master_files  
WHERE database_id = DB_ID(N'tempdb');
'@ 

