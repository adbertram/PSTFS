<#
	===========================================================================
	Filename:		PSTFS.psm1
	-------------------------------------------------------------------------
	Module Name:	PSTFS
	===========================================================================
#>

Set-StrictMode -Version Latest

function TestBuildTaskPrerequisites
{
	[OutputType([bool])]
	[CmdletBinding()]
	param
	(
		[Parameter(Mandatory)]
		[ValidateNotNullOrEmpty()]
		[string]$FolderPath
	)
	
	function TestImage {
		param($FilePath)

		Add-Type -AssemblyName 'System.Drawing'
		$img = [System.Drawing.Image]::FromFile($FilePath)
		if (($img.Size.Width -eq 32) -and ($img.Size.Height -eq 32)) {
			$true
		} else {
			$false
		}
		$img.Dispose()

	}

	## If an icon exists, it's 32x32
	$iconFilePath = "$FolderPath\icon.png"
	if ((Test-Path -Path $iconFilePath -PathType Leaf) -and (-not (TestImage -FilePath $iconFilePath)))
	{
		throw 'The icon in the build task folder is not 32x32.'
	}

	## Ensure a task.json file exists and a task ID is a GUID
	$taskPath = "$FolderPath\task.json"
	if (-not (Test-Path -Path $taskPath -PathType Leaf))
	{
		throw "The file task.json was not found inside of folder '$_'"
	}
	else
	{
		$taskJson = (Get-Content -Path $taskPath) -join "`n" | ConvertFrom-Json
		try {
			$null = [guid]$taskJson.Id
		} catch {
			throw "The ID in task.json was not a valid GUID."
		}
	}

	## Ensure the visibility value is correct: Can be: Build, Release and Preview or all.
	$visDiffs = Compare-Object -ReferenceObject $task.visibility -DifferenceObject @('Build','Release','Preview')
	if ($visDiffs | Where-Object {$_.SideIndicator -eq '<='})
	{
		throw 'One or more visibility settings are not allowed.'
	}

	## Ensure a PowerShell script exists and it's in the task.json
	$targetScriptName = $taskJson.execution.PowerShell.target | Split-Path -Leaf
	if (-not (Get-ChildItem -Path $FolderPath -Filter '*.ps1' | Where-Object { $_.Name -eq $targetScriptName }))
	{
		throw 'The PowerShell script defined in the task.json could not be found in the folder.'
	}
}

function New-TfsBuildTask
{
	<#
		.SYNOPSIS
			This function creates a TFS build task from a local folder. The folder contents must contain all of the
			required components in order to successfully create a build task. Before creation, all of these prereqs
			are tested.
	
		.EXAMPLE
			PS> New-TfsBuildTask -FolderPath C:\BuildTask -TfsUrl http:\\tfs:8080

		.PARAMETER FolderPath
			 A mandatory string parameter representing the path to the folder containing the build task contents.

		.PARAMETER TfsUrl
			 A mandatory string parameter representing the URL to the TFS server. This is typically in the form of
			 http://<Server>:8080.

		.PARAMETER Overwrite
			 A optional	switch parameter that forces an overwrite of an existing build task if one exists. By default,
			 the function will not overwrite any existing task.

		.PARAMETER Credential
			 A optional pscredential parameter representing an alternate credential to authenticate to the TFS server.
			 By default, this function uses the currently logged on user's credentials.
	
	#>
	[OutputType([void])]
	[CmdletBinding()]
		param(
		[Parameter(Mandatory)]
		[ValidateNotNullOrEmpty()]
		[ValidateScript({ 
			if (-not (Test-Path -Path $_ -PathType Container)) {
				throw "The folder '$_' is not available"
			}
			$true
		
		})]
		[string]$FolderPath,

		[Parameter(Mandatory)]
		[ValidateNotNullOrEmpty()]
		[string]$TfsUrl,

		[Parameter()]
		[ValidateNotNullOrEmpty()]
		[switch]$Overwrite,
		
		[Parameter()]
		[ValidateNotNullOrEmpty()]
		[pscredential]$Credential
	)
	try
	{
		TestBuildTaskPrerequisites -FolderPath $FolderPath

		# Load task definition from the JSON file
		$taskDefinition = (Get-Content "$FolderPath\task.json") -join "`n" | ConvertFrom-Json

		# Zip the task content
		Write-Verbose 'Zipping task content...'
		$zipFilePath = "$Env:Temp\$($taskDefinition.Id).zip"
		Get-ChildItem -Path $FolderPath | Compress-Archive -DestinationPath $zipFilePath -Force

		# Prepare to upload the task
		$taskZipItem = Get-Item $zipFilePath
		
		$headers = @{ 
			'Accept' = 'application/json; api-version=2.0-preview'
			'X-TFS-FedAuthRedirect' = 'Suppress' 
		}
		$headers.Add("Content-Range", "bytes 0-$($taskZipItem.Length - 1)/$($taskZipItem.Length)")
		
		$url = ('{0}/_apis/distributedtask/tasks/{1}' -f $TfsUrl, $taskDefinition.id)
		
		if ($Overwrite.IsPresent) 
		{
			$url += "?overwrite=true"
		}

		$restParams = @{
			Uri = $url
			Headers = $headers
			ContentType = 'application/octet-stream'
			Method = 'Put'
			InFile = $taskZipItem
		}
		if ($PSBoundParameters.ContainsKey('Credential'))
		{
			$restParams.Credential = $Credential
		} 
		else
		{
			$restParams.UseDefaultCredentials = $true
		}

		Write-Verbose -Message 'Uploading task...'
		Invoke-RestMethod @restParams
	} 
	finally 
	{
		Remove-Item -Path $zipFilePath -Recurse -ErrorAction Ignore
	}
}