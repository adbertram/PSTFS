#region import modules
$ThisModule = "$($MyInvocation.MyCommand.Path -replace '\.Tests\.ps1$', '').psm1"
$ThisModuleName = (($ThisModule | Split-Path -Leaf) -replace '\.psm1')
Get-Module -Name $ThisModuleName -All | Remove-Module -Force
Import-Module -Name $ThisModule -Force -ErrorAction Stop
#endregion

InModuleScope $ThisModuleName {
	describe 'New-TfsBuildTask' {

		$commandName = 'New-TfsBuildTask'
		$command = Get-Command -Name $commandName

		#region Mocks
			mock 'TestBuildTaskPrerequisites'

			mock 'Get-Content' {
				'{Id: "foo"}'
			}

			mock 'Get-ChildItem'

			mock 'Test-Path' {
				$true
			}

			mock 'Compress-Archive'

			mock 'Invoke-RestMethod'

			mock 'Get-Item' {
				$obj = New-MockObject -Type 'System.IO.FileInfo'
				$obj | Add-Member -Type NoteProperty -Name Length -Value 100 -PassThru -Force
			}

			mock 'Remove-Item'
		#endregion
		
		$parameterSets = @(
			@{
				FolderPath = 'C:\FolderPath'
				TfsUrl = 'tfsurlhere'
			}
		)

		$testCases = @{
			All = $parameterSets
		}

		it 'returns nothing' -TestCases $testCases.All {
			param($FolderPath,$TfsUrl,$Overwrite,$Credential)

			& $commandName @PSBoundParameters | should benullorempty

		}

		it 'invokes the API with the correct headers' -TestCases $testCases.All {
			param($FolderPath,$TfsUrl,$Overwrite,$Credential)
		
			$result = & $commandName @PSBoundParameters

			$assMParams = @{
				CommandName = 'Invoke-RestMethod'
				Times = 1
				Exactly = $true
				Scope = 'It'
				ParameterFilter = { 
					$Headers.Accept -eq 'application/json; api-version=2.0-preview' -and
					$Headers.'X-TFS-FedAuthRedirect' -eq 'Suppress' -and
					$Headers.'Content-Range' -eq 'bytes 0-99/100'
				}
			}
			Assert-MockCalled @assMParams
		}

		it 'invokes the API with the correct URL' -TestCases $testCases.All {
			param($FolderPath,$TfsUrl,$Overwrite,$Credential)
		
			$result = & $commandName @PSBoundParameters

			$assMParams = @{
				CommandName = 'Invoke-RestMethod'
				Times = 1
				Exactly = $true
				Scope = 'It'
				ParameterFilter = { $Uri -eq "$TfsUrl/_apis/distributedtask/tasks/foo" }
			}
			Assert-MockCalled @assMParams
		}

		context 'When the folder contents do not pass the prereq check' {
			
			mock 'TestBuildTaskPrerequisites' {
				throw
			}

			it 'throws an exception' -TestCases $testCases.All {
				param($FolderPath,$TfsUrl,$Overwrite,$Credential)
			
				$params = @{} + $PSBoundParameters
				{ & $commandName @params } | should throw 
			}

		}
	}
}