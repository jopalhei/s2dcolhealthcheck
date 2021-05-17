Import-Module Storage
Import-Module FailoverClusters

$PathtoHealthTest = "C:\Users\jopalhei\Documents\CaseBuddy.CaseData\120090921001855_Owen\2020-09-18\HealthTest-DOCL-20200918-1356\"
$PathtoHealthTest = $PathtoHealthTest.TrimEnd()

if ($PathtoHealthTest.EndsWith("\"))
{
    $PathtoHealthTest = $PathtoHealthTest.Substring(0,($PathtoHealthTest.Length)-1)
}
    

$PathtoJson = "C:\Users\jopalhei\Documents\CaseBuddy.CaseData\120090921001855_Owen\2020-10-28\extents.json"

$pds = Import-Clixml $PathtoHealthTest\GetPhysicalDisk.XML
$Nodes = Import-Clixml $PathtoHealthTest\GetClusterNode.XML
$vds = Import-Clixml $PathtoHealthTest\GetVirtualdisk.xml
$pool = Import-Clixml $PathtoHealthTest\GetStoragePool.XML
$poolname = $pool.FriendlyName
$json = Get-Content -Path $PathtoJson | Out-String | ConvertFrom-Json
$data = $json."$PoolName"

#Function to get Node from Disk ID

function Get-NodeOwnerPD{
    Param ($deviceNumber)
    $NodeId = [int][System.Math]::Floor($deviceNumber/1000)
    $node = $nodes | where id -EQ $NodeId
    Return $Node
}
function Get-PDVDID{
    Param ($VD)
    $Vdobjid = $vd.ObjectId.Substring($vd.ObjectId.LastIndexOf("{"),(($vd.ObjectId.LastIndexOf("}")-($vd.ObjectId.LastIndexOf("{"))+1)))
    Return $Vdobjid
}

function Get-TotalExtents{
    Param ($SpaceRecordId)
    $ExtentCount = ($data.Extents | Where SpaceRecordId -eq $SpaceRecordId).Count
    Return $ExtentCount
    
}

function Get-SpaceRecordId{
    Param ($vdid)
    $Space = $data.Spaces | Where SpaceId -eq $vdid
    $SpaceRecordId = $Space.RecordId
    Return $SpaceRecordId
}

function Get-PDperNode{
    Param ($Node)
    $nodeId = $Node.Id
    $pdsperNode = $pds | where DeviceId -Like $nodeId*
    Return $pdsperNode
}

function Get-extentsperpd{
    Param ($pd,$vdSpaceRecordId)
    $pdId = Get-PDVDID -VD $pd
    $DriveRecord = $Data.Drives | Where DriveId -eq $pdId
    $DriveRecordId = $DriveRecord.Recordid 
    $count = ($data.Extents | where {$_.DriveRecordId -eq $DriveRecordId -and $_.SpaceRecordId -eq $vdSpaceRecordId}).Count
    Return $count
}

function Get-PDwithDriveRecordId{
    Param ($DriveRecordId)
    $DriveId = ($data.Drives | Where Recordid -eq $DriveRecordId).DriveId
    $PD = $pds | Where objectid -Match $DriveId
    Return $PD
}

$BadColumns = @()
foreach($vd in $vds)
{
    $badColThisVd = 0
    #Only Supports Mirror Virtual Disks 
    If ($vd.ResiliencySettingName -ne "Mirror")
    {
        Write-Host "Virtual Disk " $Vd.FriendlyName " is not a mirror, skipping" -BackgroundColor Yellow
        Continue
    }

    $VdId = Get-PDVDID -VD $vd
    $SpaceRecordId = Get-SpaceRecordId -vdid $VdId
    
    ##### Let's look Column per Column and get the Column where we see that multiple copies reside on the same fault domain
    $vdExtents = $data.Extents | where spacerecordid -eq $SpaceRecordId

    #Let's group them by Offset (each offset will have extents = ColumnCount*NumberofDatacopies)
    $vdExtentsOffset = $vdExtents | Group-Object SpaceOffset -AsHashTable -AsString

    foreach($offset in $vdExtentsOffset.Keys)
    {
        #Now let's Group them by Columns
        $columns = $vdExtentsOffset.Item($offset) | Group-Object ColumnNumber -AsHashTable -AsString

        foreach($column in $columns.Keys)
        {
            $currColumn = $columns.Item($column)
            if($vd.NumberOfDataCopies -ne $currColumn.Count) #this should never happen on healthy Virtual Disks
            {
                Write-Host "For Virtual Disk " $vd.FriendlyName " on Offset " $offset " Column "  $column " we do not have the expected " + $vd.NumberOfDataCopies + " copies" -BackgroundColor Red
                Continue
            }
            
            $nodearray = @()
            foreach($copy in $currColumn)
            {
                $PD = Get-PDwithDriveRecordId -DriveRecordId $copy.DriveRecordId 
                $node = Get-NodeOwnerPD -deviceNumber $pd.DeviceId
                if ($nodearray.Contains($node))
                {
                    $BadColumns += $currColumn
                    ++$badColThisVd
                }
                else{$nodearray += $node}
            }

        }
    }
    if ($badColThisVd -gt 0)
    {
        Write-host -ForegroundColor Red "The Virtual Disk "$vd.FriendlyName" contains "$badColThisVd" bad columns."
    }
    else {
        Write-Host -ForegroundColor Green "Virtual Disk " + $vd.FriendlyName + " is ok."
    }

}
If ($BadColumns.Count -gt 0)
{
    $datetime = Get-Date -Format "ddMMyyHHmmss"
    $filename = $PathtoHealthTest + "\" + $vd.FriendlyName + "_badcolumns_" + $datetime + ".xml"
    Write-Host -ForegroundColor Red "Issues were found, a total of "$BadColumns.Count" columns impacted, please check the output file on "$filename
    $BadColumns | Export-Clixml -Path $filename
}







