# JSON_Format_Merge
#
# Formats raw JSON files from SCCM Run Scripts output of 'GetLogonEvents' script
# Cleans up formatting errors and removes truncated JSON outputs
# Creates additional columns for BaseName, Delta, & Bandwidth
# Performs calculations and cleanup on data
# Creates csv file for each JSON file (per base)
# Merges all csvs into single 'all_bases.csv'
#
# v3
# Removed Bandwidth event row from logon sessions

# Start JSON Formatting & CLeanup #
Get-ChildItem "C:\Temp\JSONOutput" -Filter *.txt | 
Foreach-Object {

    $SessionIDs = @()
    $JsonFile = ""
    $JsonArray = ""
    $JSONElement = ""
    $JSONNew = ""
    $NewJSONFile = "[`n"
    $FormattedJSON = ""

    $JsonFile = get-content -Raw $_.FullName
    $JSONArray = $JSONFile -split("\[")
    $BaseName = $_.BaseName

    ForEach ($JSONElement in $JSONArray) {
        If ($JSONElement.Length -gt 1) {

            #Cleanup string                
            $JSONElement = $JSONElement.Trim()
            $JSONElement = $JSONElement.replace("`n","")
            $JSONElement = $JSONElement.replace("`r`n","")

            #get last character in string
            $LastChar = $JSONElement.Substring($JSONElement.get_Length()-1)
            #$LastChar

            #Remove truncated output
            If ($LastChar -ne "]") {
            }
            #Output Ok - add to new JSON variable
            Else {
                $JSONElement =$JSONElement.Substring(0,$JSONElement.Length-2)
                $JSONNew = $JSONElement + ",`n"
                $NewJSONFile += $JSONNew
            }
        }
    }

    $NewJSONFile = $NewJSONFile.Substring(0,$NewJSONFile.Length-2)
    $NewJSONFile = $NewJSONFile.Replace("{{","{")
    $NewJSONFile += "`r`n]"
    $FormattedJSON = $NewJSONFile | Out-String | ConvertFrom-Json

    # End JSON Formatting & CLeanup #

    # Get Unique SessionID Values
    ForEach ($Node in $FormattedJSON) {
        $SessionIDs += $Node.SessionID
        $Node | Add-Member -MemberType NoteProperty -Name 'Delta' -Value ""
        $Node | Add-Member -MemberType NoteProperty -Name 'BaseName' -Value $BaseName
        $Node | Add-Member -MemberType NoteProperty -Name 'Bandwidth' -Value ""
    }
    $UniqueSessions = $SessionIDs | Sort-Object | Get-Unique

    #Loop through each Unique SessionID Value
    ForEach ($SessionID in $UniqueSessions) {
        $AuthStartTime = ""
        $Bandwidth = ""

        # Get Auth Start Time from Winlogon Event TimeCreated
        $AuthStartTime = ($FormattedJSON | where {$_.SessionID -eq $SessionID -and $_.ActivityName -eq "Authentication Start"}).TimeCreated
        $Bandwidth = ($FormattedJSON | where {$_.SessionID -eq $SessionID -and $_.EventID -eq 5314}).Duration

        #Add Bandwidth speed value
        If ($Bandwidth) {
            $Node | Add-Member -MemberType NoteProperty -Name 'Bandwidth' -Value $Bandwidth -Force
        }

        # If Auth Start Time is Found for this session
        If ($AuthStartTime) {

            # Loop through each Node in this Unique Session and add Delta Value
            ForEach ($Node in ($FormattedJSON | where {$_.SessionID -eq $SessionID})) {
                $DeltaMS = ""
                If ($AuthStartTime -is [array]) {
                }
                Else {
                    $Delta = [datetime]$Node.TimeCreated - [datetime]$AuthStartTime
                    $DeltaMS = [int]$Delta.TotalMilliseconds
                    #$DeltaMS

                    $Node | Add-Member -MemberType NoteProperty -Name 'Delta' -Value $DeltaMS -Force

                    If ($Node.ActivityName -eq "Authentication Complete") {
                        $Node | Add-Member -MemberType NoteProperty -Name 'Duration' -Value $DeltaMS -Force
                    }
                }
            } #End For Node Loop
        } # End If

    } # End For SessionID Loop

    # Remove Negative Delta values
    $OutputJSON = $FormattedJSON | Where {$_.Delta -ge 0 -and $_.EventID -ne 5314}

    $FileOut = "$PSScriptRoot\" + $_.BaseName + ".csv"
    $OutputJSON | select * | export-csv ($FileOut) -NoTypeInformation
    Write-Output "$FileOut successfully created" 

} #End For - Loop to next file

#Merge all csv files into one
$CSVFiles = Get-ChildItem $PSScriptRoot -Filter *.csv
$OutputFile = "$PSScriptRoot\AllBases.csv" 
$Output = @()

foreach($CSV in $CSVFiles) { 
    $CSVFullPath = $CSV.FullName
    if(Test-Path $CSVFullPath) { 
         
        $temp = Import-CSV -Path $CSVFullPath | select *
        $Output += $temp 
 
    } else { 
        Write-Warning "$CSV : No such file found" 
    } 
 
} 
$Output | Export-Csv -Path $OutputFile -NoTypeInformation 
Write-Output "$OutputFile successfully created" 
 