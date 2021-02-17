# GetLogonEvents
# 
# Queries Group policy and Winlogon event logs for logon-related activities
# Queries StartupXML files for Application startup activity during the user logon process
#
# V2
# Added individual Policy Download duration times
# Added Changes Detected bool for CSE Processing
# Added Estimated bandwidth for logon session
# Added DC and User Discovery durations
# Added DC Name being used for GPO & Script processing
#
# V3
# Updated startup application process name variable to only capture image name (removed switches)
# Updated Winlogon event search to prevent multiple logon sessions being returned


# Create array for all events that this script will return for export data at end
$EventList = @()

#Find Logon Processing GPO Events
$logonActivities = Get-WinEvent -FilterHashtable @{LogName='Microsoft-Windows-GroupPolicy/Operational';ID='4001'} -ErrorAction SilentlyContinue

# Loop through each logon Correlation ID to find/filter events for each logon
$logonActivities | ForEach-Object {
    $ActivityID = $_.ActivityID
    $UserName = ""

    #Loop through each GPO event
    $XPath = "*[System[EventID=4001 or EventID=5257 or EventID=5016 or EventID=5314 or EventID=7016 or EventID=8001] and System[Correlation[@ActivityID='$ActivityID']]]"
    $GPOEvents = Get-WinEvent -FilterXPath $Xpath -LogName 'Microsoft-Windows-GroupPolicy/Operational' -ErrorAction SilentlyContinue
    $GPOEvents | ForEach-Object {

        $TimeCreated = ""
        $MachineName = ""
        $EventID = ""
        $Action = ""
        $CSEName = ""
        $Duration = ""
        $Bandwidth = ""
        $ChangesDetected = ""
        $Event4016 = ""
        $Event4016XML = ""
        $Operation = ""

        
        #Convert to XML
        $GPOEvent = [xml]$_.ToXml()

        #Get Variables
        $TimeCreated = $_.TimeCreated
        $MachineName = $_.MachineName
        $EventID = $_.Id

        switch($eventID){
            4001 {$Action = "GPO Start"
                  $UserName = ($GPOEvent.Event.EventData.Data | Where-Object {$_.name -eq "PrincipalSamName"}).InnerText
                  $StartPolicy = $TimeCreated
                  $CSEName = "GPO Start"
                  $WinlogonSearchStart = $StartPolicy.AddMinutes(-1)
                  $WinlogonSearchStop = $StartPolicy
                  }
            5314 {$Action = "Bandwidth"
                  $CSEName = "Bandwidth"
                  $Duration = ($GPOEvent.Event.EventData.Data | Where-Object {$_.name -eq "BandwidthInkbps"}).InnerText
                  }
            5257 {$Action = "Download Policies"
                  $CSEName = "All Policies"
                  $Duration = ($GPOEvent.Event.EventData.Data | Where-Object {$_.name -eq "PolicyDownloadTimeElapsedInMilliseconds"}).InnerText
                  }
            5017 {$CSEName = ($GPOEvent.Event.EventData.Data | Where-Object {$_.name -eq "Parameter"}).InnerText
                  $Duration = ($GPOEvent.Event.EventData.Data | Where-Object {$_.name -eq "OperationElaspedTimeInMilliSeconds"}).InnerText
                  $Operation = ($GPOEvent.Event.EventData.Data | Where-Object {$_.name -eq "OperationDescription"}).InnerText
                  If ($Operation -eq "%%4132") {$Action = "Download Policies"}
                  If ($Operation -eq "%%4120") {$Action = "Discover DC"}
                  If ($Operation -eq "%%4118") {$Action = "Discover User"}
                  } 
            {$_ -in 5016,7016} {$Action = "CSE Processing"
                  $CSEName = ($GPOEvent.Event.EventData.Data | Where-Object {$_.name -eq "CSEExtensionName"}).InnerText
                  $Duration = ($GPOEvent.Event.EventData.Data | Where-Object {$_.name -eq "CSEElaspedTimeInMilliSeconds"}).InnerText
                  # Query corresponding event 4016 to see if policy changes detected
                  $XPath = "*[System[EventID=4016] and System[Correlation[@ActivityID='$ActivityID']] and EventData[(Data[@Name='CSEExtensionName']='$CSEName')]]"
                  $Event4016 = Get-WinEvent -FilterXPath $Xpath -LogName 'Microsoft-Windows-GroupPolicy/Operational' -ErrorAction SilentlyContinue
                  $Event4016XML = [xml]$Event4016.ToXml()
                  $ChangesDetected = ($Event4016XML.Event.EventData.Data | Where-Object {$_.name -eq "IsGPOListChanged"}).InnerText
                  }
            8001 {$Action = "GPO Complete"
                  $CSEName = "GPO Complete"
                  $UserName = ($GPOEvent.Event.EventData.Data | Where-Object {$_.name -eq "PrincipalSamName"}).InnerText
                  $DurationInSec = ($GPOEvent.Event.EventData.Data | Where-Object {$_.name -eq "PolicyElaspedTimeInSeconds"}).InnerText
                  $Duration = [int]$DurationInSec * 1000
                  $StopPolicy = $TimeCreated.AddMinutes(1)
                  $EndScriptSearch = $TimeCreated.AddMinutes(10)
                  }
            } #End Switch

        $obj = New-Object -TypeName PSCustomObject -Property @{
            SessionID = $ActivityID.Guid
            TimeCreated = $TimeCreated.ToString("MM/dd/yyyy HH:mm:ss.fff")
            MachineName = $MachineName
            EventID = $EventID
            Action = $Action
            ActivityName = $CSEName
            UserName = $UserName
            Duration = $Duration
            ChangesDetected = $ChangesDetected
            }

        $EventList += $obj

        } # End Loop through each logon event


    #Find Logon Scripts During time preiod
    $scriptEvents = Get-WinEvent -FilterHashtable @{LogName='Microsoft-Windows-GroupPolicy/Operational';ID='4018','5018';StartTime=$StartPolicy;EndTime=$EndScriptSearch} -ErrorAction SilentlyContinue
    $scriptEvents | ForEach-Object {
        $ScriptEvent = [xml]$_.ToXml()

        $TimeCreated = ""
        $MachineName = ""
        $EventID = ""
        $Action = ""
        $CSEName = ""
        $Duration = ""

        #Get Variables
        $TimeCreated = $_.TimeCreated
        $MachineName = $_.MachineName
        $EventID = $_.Id
    
        If (($ScriptEvent.Event.EventData.Data | Where-Object {$_.name -eq "ScriptType"}).InnerText -eq 1) {
            
            $UserName = ($ScriptEvent.Event.EventData.Data | Where-Object {$_.name -eq "PrincipalSamName"}).InnerText

            switch($EventID){
                4018 {$Action = "Logon Script Start"}
                5018 {$Action = "Logon Script Complete"
                      $DurationInSec = ($ScriptEvent.Event.EventData.Data | Where-Object {$_.name -eq "ScriptElaspedTimeInSeconds"}).InnerText
                      $Duration = [int]$DurationInSec * 1000}
            } # End Switch

            $obj = New-Object -TypeName PSCustomObject -Property @{
            SessionID = $ActivityID.Guid
            TimeCreated = $TimeCreated.ToString("MM/dd/yyyy HH:mm:ss.fff")
            MachineName = $MachineName
            EventID = $EventID
            Action = $Action
            ActivityName = $Action
            UserName = $UserName
            Duration = $Duration
            }

            $EventList += $obj

        } # End If
    } # End Find Logon Scripts Loop

    #Find Winlogon events During time preiod
    $AuthActivities = Get-WinEvent -FilterHashtable @{LogName='Microsoft-Windows-Winlogon/Operational';ID='1','2';StartTime=$WinlogonSearchStart;EndTime=$WinlogonSearchStop} -ErrorAction SilentlyContinue
    $LogonCompleteEvents = $AuthActivities | Where-Object {$_.Id -eq 2} -ErrorAction SilentlyContinue
    If ($LogonCompleteEvents) {
        If ($LogonCompleteEvents -is [array]) {
            $LogonComplete = $LogonCompleteEvents[-1]
        }
        Else {$LogonComplete = $LogonCompleteEvents}

        #Get Variables
        $TimeCreated = $LogonComplete.TimeCreated
        $MachineName = $LogonComplete.MachineName
        $EventID = $LogonComplete.Id

        $obj = New-Object -TypeName PSCustomObject -Property @{
            SessionID = $ActivityID.Guid
            TimeCreated = $TimeCreated.ToString("MM/dd/yyyy HH:mm:ss.fff")
            MachineName = $MachineName
            EventID = $EventID
            Action = "Authentication Complete"
            ActivityName = "Authentication Complete"
            UserName = $UserName
            Duration = ""
            }
        $EventList += $obj
    }

    $LogonStartEvents = $AuthActivities | Where-Object {($_.Id -eq 1) -and ($_.TimeCreated -lt $LogonComplete.TimeCreated)} -ErrorAction SilentlyContinue
    If ($LogonStartEvents) {
        If ($LogonStartEvents -is [array]) {
            $LogonStart = $LogonStartEvents[-1]
        }
        Else {$LogonStart = $LogonStartEvents}

        #Get Variables
        $TimeCreated = $LogonStart.TimeCreated
        $MachineName = $LogonStart.MachineName
        $EventID = $LogonStart.Id

        $obj = New-Object -TypeName PSCustomObject -Property @{
            SessionID = $ActivityID.Guid
            TimeCreated = $TimeCreated.ToString("MM/dd/yyyy HH:mm:ss.fff")
            MachineName = $MachineName
            EventID = $EventID
            Action = "Authentication Start"
            ActivityName = "Authentication Start"
            UserName = $UserName
            Duration = ""
            }
        $EventList += $obj
    }
    # End Winlogon Auth Activities

    #Find Desktop launch events during logon timeperiod
    $DesktopAvail = Get-WinEvent -FilterHashtable @{LogName='Microsoft-Windows-GroupPolicy/Operational';ID='6339';StartTime=$StartPolicy;EndTime=$StopPolicy} -ErrorAction SilentlyContinue
        $DesktopAvail | ForEach-Object {

        $TimeCreated = ""
        $MachineName = ""
        $EventID = ""
        $Action = ""
        $CSEName = ""
        $Duration = ""

        #Get Variables
        $TimeCreated = $_.TimeCreated
        $MachineName = $_.MachineName
        $EventID = $_.Id
        $Action = "Desktop Initialize"

        $obj = New-Object -TypeName PSCustomObject -Property @{
            SessionID = $ActivityID.Guid
            TimeCreated = $TimeCreated.ToString("MM/dd/yyyy HH:mm:ss.fff")
            MachineName = $MachineName
            EventID = $EventID
            Action = $Action
            ActivityName = $Action
            UserName = $UserName
            Duration = $Duration
        }
        $EventList += $obj
        } # Loop through Desktop Launch events

    #Find Application launch events
    #Convert to XML
    $AppEvent = [xml]$_.ToXml()

    #Get Variables
    $TimeCreated = $_.TimeCreated
    $MachineName = $_.MachineName
    $EventID = $_.Id
    $UserName = ($AppEvent.Event.EventData.Data | Where-Object {$_.name -eq "PrincipalSamName"}).InnerText
    $GPOProcessStart = $TimeCreated
    $StartPolicy = $TimeCreated
    $EndScriptSearch = $TimeCreated.AddMinutes(10)

    $StartupXMLFile = Get-ChildItem "C:\Windows\System32\WDI\LogFiles\StartupInfo" | Where-Object {($_.LastWriteTime -gt $StartPolicy) -and ($_.LastWriteTime -lt $EndScriptSearch) } -ErrorAction SilentlyContinue
    
    If  (!$StartupXMLFile.FullName) {} # StartupInfo XML file Not Found for logon session!
    Else {

        [xml]$StartupXMLContent = Get-Content -path $StartupXMLFile.FullName

        #Loop through each Process
        ForEach ($ProcessItem in $StartupXMLContent.StartupData.Process) {

            
            $ProcessTime = $ProcessItem.StartTime
            $ProcessDateTime = [datetime]::ParseExact($ProcessTime, 'yyyy/MM/dd:HH:mm:ss.fffffff', [System.Globalization.CultureInfo]::InvariantCulture)
            $ProcessLocalTime = $ProcessDateTime.ToLocalTime()
            $ProcessName = $ProcessItem.CommandLine.'#cdata-section'
            $ProcessNameShort = $ProcessName.split("\")[-1]
            $ProcessNameShort = $ProcessNameShort.split('"')[0]


            $obj = New-Object -TypeName PSCustomObject -Property @{
            TimeCreated = $ProcessLocalTime.ToString("MM/dd/yyyy HH:mm:ss.fff")
            UserName = $UserName
            Action = "Application Launch"
            EventID = "StartupInfo.xml"
            MachineName = $MachineName
            SessionID = $ActivityID.Guid
            Duration = ""
            ActivityName = $ProcessNameShort
            #ProcessParent = $ProcessItem.ParentName
            }
            $EventList += $obj


        } # End ForEach - Create Obj
    } # End If/Else

} # End Loop through each logon Correlation ID (ActivityID)

#Final Output
$EventList | Export-Csv -Path "C:\Temp\LogonTimelines.csv" -NoTypeInformation