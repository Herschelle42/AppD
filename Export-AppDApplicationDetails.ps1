<#
.SYNOPSIS
  Export the latest version of the AppD Application.
.DESCRIPTION
  Exports the following information into a text file.
  Basic Blueprint information
  List of Nodes (think external services, machines) and the Components (think software components) on them
  Details of Nodes, such as NIC and Disks
  Details of Components, Properties and scripts
  
  This allows
.NOTES
  Author: Clint Fritz
  Enhancements: Add Parameters
                Clean up code
                Revisit propDef custom object creation
                Reorder Properties to match vRA7 software component property order
                Remove launching of report file (or add as a parameter)
		Collect Dependencies between software components
		Trim lines for trailing spaces?
#>

[array]$applicationList = ("Siebel v11")

$reportPath = ".\My Documents"

$serverUri = "https://paas.corp.local"
$apiPath = "/darwin/api/2.0"

$apiUri = "$($serverUri)$($apiPath)"

if (-not($credAppD)) {
    $credAppD = Get-Credential -Message "Enter AppD Credentials"
}
$headers = @{"Content-Type"="application/json"; "Accept"="application/json"}

Write-Verbose "[INFO] Get list of all the applications"
$uri = "$($apiUri)/application?page=0&page-size=100"
Write-Verbose "[INFO] uri: $($uri)"

$allApplications = ($request).Content | ConvertFrom-Json | Select -ExpandProperty results

foreach ($appName in $applicationList)
{
    $thisApp = $allApplications | ? { $_.name -eq $appName } 
    Write-Verbose "[INFO] Application: $($thisApp.name)"
    [string]$reportData = $null

    $reportData += "+====================================================================================+`r`n"
    $reportData += "| Name:        $($thisApp.name)`r`n"
    $reportData += "| Description: $($thisApp.description)`r`n"
    $version = $thisApp.applicationVersions | Sort id -Descending | Select -First 1 | Select -ExpandProperty Version
    #Example of how to get a particular version.
    #$version = $thisApp.applicationVersions | ? { $_.Version.Major -eq 1 -and $_.Version.Minor -eq 1 } | Select -ExpandProperty Version
    Write-Verbose "[INFO] Version: $($version.major).$($version.minor)"
    $reportData += "| Version:     $($version.major).$($version.minor)`r`n"
    $reportData += "+====================================================================================+`r`n"

    [string]$outputFile = "$($reportPath)\AppD Export - $($thisApp.name) v$($version.major).$($version.minor).txt"
    Write-Verbose "[INFO] output File: $($outputFile)"

    $reportData += "Blueprint Nodes`r`n"

    #Getting the latest version of the application
    $versionId = $thisApp.applicationVersions | Sort id -Descending | Select -First 1 | Select -ExpandProperty id
    #$versionId = $thisApp.applicationVersions | ? { $_.Version.Major -eq 1 -and $_.Version.Minor -eq 1 } | Select -ExpandProperty id
    Write-Verbose "[INFO] VersionID: $($versionId)"

    $uri = "$($apiUri)/blueprint/$($versionId)"
    Write-Verbose "[INFO] uri: $($uri)"
    $request = Invoke-WebRequest -UseBasicParsing -Uri $uri -Method GET -WebSession $AppD
    
    $blueprint = ($request.Content | ConvertFrom-Json).result
    Write-Verbose "[INFO] $($blueprint.nodes | Select name, id | sort name | Out-String -Width 300)"
    $reportData += "$($blueprint.nodes | Select name | Sort name | Out-String -Width 300)"
    

    Write-Verbose "[INFO] Get the respective Component Ids."
    $sncList = foreach ($node in $blueprint.nodes | Sort name)
    {
        Write-Verbose "[INFO] - Node Name: $($node.name)"
        $reportData += "+-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=--=-=-=-=-=-=-=-=-=-+`r`n"
        $reportData += "| Node: $($node.name)`r`n"
        $reportData += "+-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=--=-=-=-=-=-=-=-=-=-+`r`n"
        if ($node.serviceNodeComponents){
            $snc = $null
            foreach ($snc in $node.serviceNodeComponents | sort name)
            {
                Write-Verbose "[INFO] --- Component Name: $($snc.name)"
                $hash = [ordered]@{}
                $hash.NodeName = $node.name
                $hash.NodeId = $node.id
                $hash.ComponentName = $snc.name
                $hash.ComponentId = $snc.id
                #$hash.SvcVerUri = $snc.serviceRef.uri
                $hash.SvcVerUri = "service-version"
                $hash.SvcVerId = $snc.serviceRef.id
                $object = new-object PSObject -property $hash
                $object    
            }#end foreach snc
        }#end if snc

        if ($node.externalServiceNodeComponent){
            $snc = $null
            foreach ($snc in $node.externalServiceNodeComponent | sort name)
            {
                Write-Verbose "[INFO] --- Component Name: $($snc.name)"
                $hash = [ordered]@{}
                $hash.NodeName = $node.name
                $hash.NodeId = $node.id
                $hash.ComponentName = $snc.name
                $hash.ComponentId = $snc.id
                #$hash.SvcVerUri = $snc.externalServiceVersionRef.uri
                $hash.SvcVerUri = "external-service-version"
                $hash.SvcVerId = $snc.externalServiceVersionRef.id
                $object = new-object PSObject -property $hash
                $object    
            }#end foreach snc
        }#end if esnc

        Write-Verbose "[INFO] Details"
        $reportData += "Details`r`n"
        $reportData += "-------"
        $reportData += "$($node | Select name, cluster, clustersize, vcpuCount, memoryMb, @{Name="OSVersion"; Expression={$_.osVersionRef.name}} | Out-String -Width 300)`r`n"

        Write-Verbose "[INFO] NICS"
        $reportData += "$($node.nics | Select @{Name="NIC Name"; Expression={$_.name}}, @{Name="Logical Network Name"; Expression={$_.networkName}} | Out-String -Width 300)`r`n"
        
        Write-Verbose "[INFO] Disks"
        $reportData += "Disks`r`n"
        $reportData += "-----"
        
        $disklist = foreach ($disk in $node.disks) {

            $hash = [ordered]@{}
            $hash.Name = $node.disks.name
            $hash.MountPoint = $disk.properties | ? { $_.propertyDefinition.name -match "MountPoint" } | Select -ExpandProperty Value
            $hash.FileSystem = $disk.properties | ? { $_.propertyDefinition.name -match "FileSystem" } | Select -ExpandProperty Value
            $hash.SizeGB = $disk.properties | ? { $_.propertyDefinition.name -match "DiskSize" } | Select -ExpandProperty Value
            $hash.Tags = $disk.properties | ? { $_.propertyDefinition.name -match "Tags" } | Select -ExpandProperty Value
            $hash.Description = $node.disks.description
            $object = new-object PSObject -property $hash
            $object

        }#end foreach Disk
        $reportData += "$($disklist | ft | Out-String -Width 300)`r`n"

        #$tempData = ""
        #Write-Verbose "[INFO] $($tempData)"

    }#end foreach node

    $reportData += "+------------------------------------------------------------------------------------+`r`n"
    $reportData += "| Node and Component List                                                            |`r`n"
    $reportData += "+------------------------------------------------------------------------------------+`r`n"

    Write-Verbose "[INFO] SNCList $($sncList | ft | Out-String -Width 300)"
    $reportData += "$($sncList | sort SvcVerUri -Descending | sort NodeName, ComponentName | Select NodeName, ComponentName | Out-String)`r`n"


    foreach ($snc in $sncList | Sort NodeName, ComponentName)
    {
        Write-Verbose "[INFO] Component: $($snc.ComponentName)"
        $SvcVerUri = $snc.SvcVerUri
        $SvcVerId = $snc.SvcVerId

        #Get the Properties of each Component.
        $reportData += "+------------------------------------------------------------------------------------+`r`n"
        $reportData += "| Component: $($thisApp.name) \ $($snc.NodeName) \ $($snc.ComponentName)`r`n"
        $reportData += "+------------------------------------------------------------------------------------+`r`n"
        $reportData += "`r`n"

        $uri = "$($apiUri)/$($SvcVerUri)/$($SvcVerId)"
        Write-Verbose "[INFO] uri: $($uri)"
        $request = Invoke-WebRequest -UseBasicParsing -Uri $uri -Method GET -WebSession $AppD

        $componentProperties = ($request.Content | ConvertFrom-Json).result

        Write-Verbose "[INFO] Get Details"
        $reportData += "Details`r`n"
        $reportData += "-------`r`n"
        $reportData += "Name:                           $($snc.ComponentName)`r`n"
        $reportData += "Library Service:                $($componentProperties.name)`r`n"
        $reportData += "Version:                        $($componentProperties.version.major).$($componentProperties.version.minor)`r`n"
        $reportData += "Service Version Business Group: $($componentProperties.groupMembership[0].ownerGroupRef.name)`r`n"
        $reportData += "Description:                    $($componentProperties.description)`r`n"
        $reportData += "`r`n"


        Write-Verbose "[INFO] Get Properties"
        $reportData += "Properties`r`n"
        $reportData += "----------`r`n"
        $propertyList = foreach ($property in $componentProperties.properties | sort)
        {
            $hash = [ordered]@{}

            foreach ($propDef in $property.propertyDefinition)
            {
                $hash.key = $property.propertyDefinition.key
                $hash.description = $property.propertyDefinition.description
                $hash.type = $property.propertyDefinition.type
				#Value
                $hash.secure = $property.propertyDefinition.secure
				#Overrideable
                $hash.required = $property.propertyDefinition.required
				#listValues
                $hash.id = $property.propertyDefinition.id
                $hash.lockVersion = $property.propertyDefinition.lockVersion
                $hash.name = $property.propertyDefinition.name
            }
    
            $hash.Value = $property.value
            $hash.overrideable = $property.overrideable
            $hash.listValues = $property.listValues

            $object = new-object PSObject -property $hash
            $object 
        }#end foreach property
        $reportData += "$($propertyList | Sort key | ft -AutoSize | Out-String -Width 300)`r`n"
        $reportData += "`r`n"


        Write-Verbose "[INFO] Get Actions (Scripts)"
        $reportData += "Scripts`r`n"
        $reportData += "-------`r`n"
        if ($componentProperties.scripts)
        {
            Write-Verbose "[INFO] internal Component"
            $reportData += $componentProperties.scripts | Select lifecycleStage, scriptType, script, rebootAfter | fl | Out-String -Width 300
        }

        if ($componentProperties.providerSpecificationVersionListRef)
        {
            Write-Verbose "[INFO] External Component"

            $uri = "$($apiUri)/$($SvcVerUri)/$($SvcVerId)/provider-specification-version?page=0&page-size=20"
            Write-Verbose "[INFO] uri: $($uri)"
            $request = Invoke-WebRequest -UseBasicParsing -Uri $uri -Method GET -WebSession $AppD

            $serviceVersion = ($request.Content | ConvertFrom-Json).results

            $reportData += "$($serviceVersion.scripts | Select id, lockVersion, lifecycleStage, rebootAfter, scriptType, script | fl | Out-String -Width 300)`r`n"

            #$serviceVersion.logicalTemplateVersionRef
            $reportData += "Logical Template Version:  $($serviceVersion.logicalTemplateVersionRef.name)`r`n"
        }

    }#end foreach item

    $reportData | Out-File -FilePath $outputFile -Encoding ascii
    ii $outputFile
}#end foreach app
