#Requires -Version 7.0
[CmdletBinding()] param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$fail=[Collections.Generic.List[string]]::new();$count=0
function A([bool]$ok,[string]$code){$script:count++;if(-not $ok){$fail.Add($code)}}
function Test-ThrowsExact([scriptblock]$Action,[string]$ExpectedCode){
 try{$null=& $Action;return $false}catch{return $_.Exception.Message -ceq $ExpectedCode}
}
function Get-ArrayArgumentTokenText([Management.Automation.Language.CommandAst]$Command,[string]$ParameterName){
 $elements=@($Command.CommandElements)
 for($i=0;$i -lt ($elements.Count-1);$i++){
  if($elements[$i] -is [Management.Automation.Language.CommandParameterAst] -and $elements[$i].ParameterName -ceq $ParameterName){
   $argument=$elements[$i+1]
   if($argument -isnot [Management.Automation.Language.ArrayExpressionAst]){return @()}
   $statements=@($argument.SubExpression.Statements)
   if($statements.Count -ne 1 -or $statements[0] -isnot [Management.Automation.Language.PipelineAst]){return @()}
   $pipelineElements=@($statements[0].PipelineElements)
   if($pipelineElements.Count -ne 1 -or $pipelineElements[0] -isnot [Management.Automation.Language.CommandExpressionAst]){return @()}
   $expression=$pipelineElements[0].Expression
   if($expression -isnot [Management.Automation.Language.ArrayLiteralAst]){return @()}
   return @($expression.Elements|ForEach-Object{$_.Extent.Text})
  }
 }
 return @()
}
function Get-ThriveLensParsedSource([string]$Source){
 $tokens=$null;$parseErrors=$null
 $ast=[Management.Automation.Language.Parser]::ParseInput($Source,[ref]$tokens,[ref]$parseErrors)
 return [pscustomobject]@{Ast=$ast;Tokens=@($tokens);Errors=@($parseErrors)}
}
function Test-ThriveLensSourceParses([string]$Source){
 try{$parsed=Get-ThriveLensParsedSource -Source $Source;return $parsed.Errors.Count -eq 0}catch{return $false}
}
function Get-ThriveLensFunctionAst([Management.Automation.Language.Ast]$Ast,[string]$Name){
 $functions=@($Ast.FindAll({param($node)$node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq $Name},$true))
 if($functions.Count -ne 1){return $null}
 return $functions[0]
}
function Get-ThriveLensCommandAsts([Management.Automation.Language.Ast]$Ast,[string]$Name){
 $commands=@($Ast.FindAll({param($node)$node -is [Management.Automation.Language.CommandAst] -and $node.GetCommandName() -ceq $Name},$true)|Sort-Object {$_.Extent.StartOffset})
 Write-Output -NoEnumerate $commands
}
function Test-ThriveLensAstHasAncestor([Management.Automation.Language.Ast]$Node,[type]$Type,[scriptblock]$Predicate){
 $ancestor=$Node.Parent
 while($null -ne $ancestor){
  if($ancestor -is $Type -and (& $Predicate $ancestor)){return $true}
  $ancestor=$ancestor.Parent
 }
 return $false
}
function Test-ThriveLensAstHasProcessTypeInvocation([Management.Automation.Language.Ast]$Ast,[int]$StartOffset,[int]$EndOffset){
 $processInvocations=@($Ast.FindAll({param($node)
  if($node -isnot [Management.Automation.Language.InvokeMemberExpressionAst] -or
     $node.Extent.StartOffset -lt $StartOffset -or $node.Extent.EndOffset -gt $EndOffset -or
     $node.Expression -isnot [Management.Automation.Language.TypeExpressionAst]){return $false}
  return ([string]$node.Expression.TypeName.FullName) -match '^(?i:(?:System\.)?Diagnostics\.Process(?:StartInfo)?)$'
 },$true))
 return $processInvocations.Count -gt 0
}
function Test-ThriveLensSettleHostOnlyContract([string]$Source){
 try{
  $parsed=Get-ThriveLensParsedSource -Source $Source
  if($parsed.Errors.Count -ne 0){return $false}
  $settle=Get-ThriveLensFunctionAst -Ast $parsed.Ast -Name 'Wait-ThriveLensInterCycleMemorySettle'
  if($null -eq $settle){return $false}
  $definition=$settle.Extent.Text
  $commands=@($settle.FindAll({param($node)$node -is [Management.Automation.Language.CommandAst] -and $null -ne $node.GetCommandName()},$true)|ForEach-Object{$_.GetCommandName()}|Sort-Object -Unique)
  return ($definition -match 'Get-ThriveLensFreeMemoryBytes' -and
   $definition -match '\[Diagnostics\.Stopwatch\]::StartNew\(\)' -and
   $definition -match 'Start-Sleep\s+-Milliseconds' -and
   $definition -notmatch '(?i)WSL|Stop-Process|Kill\(|Invoke-|Remove-|Set-|New-Item' -and
   ($commands -join ',') -ceq 'Get-ThriveLensFreeMemoryBytes,Start-Sleep' -and
   -not (Test-ThriveLensAstHasProcessTypeInvocation -Ast $settle -StartOffset $settle.Extent.StartOffset -EndOffset $settle.Extent.EndOffset))
 }catch{return $false}
}
function Test-ThriveLensStartCoreContract([string]$Source){
 try{
  $parsed=Get-ThriveLensParsedSource -Source $Source
  if($parsed.Errors.Count -ne 0 -or $Source -match 'Resolve-ThriveLens(?:ChildOutcome|StartChildExit|PreTokenStartObservation|StartChildFailure)'){return $false}
  $core=Get-ThriveLensFunctionAst -Ast $parsed.Ast -Name 'Invoke-ThriveLensPostgresStartUnderLock'
  if($null -eq $core){return $false}
  $parameters=@($core.Body.ParamBlock.Parameters|ForEach-Object{$_.Name.VariablePath.UserPath})
  if(($parameters -join ',') -cne 'ConfigurationLease,IdentityToken,LifecycleLock,WslTouched,StartAttempted,StartCommitResourceGateVerified'){return $false}
  $expected=@(
   'Assert-ThriveLensLifecycleLockOwnership','Assert-ThriveLensConfigurationLease','Get-ThriveLensConfigurationLeaseFingerprint',
   'Get-ThriveLensWslContract','Get-ThriveLensLeasedResourceBudget','Get-ThriveLensWslPaths','Invoke-ThriveLensResourceGate',
   'Get-ThriveLensMemoryPolicyThresholds','Get-ThriveLensFreeMemoryBytes','Assert-ThriveLensWslIdentity','Assert-ThriveLensWslPackages','Assert-ThriveLensWslInternalDisk',
   'Get-ThriveLensWslClusterState','Assert-ThriveLensWslAbsent','Assert-ThriveLensHostPortAbsent','Stop-ThriveLensDistroAndVerify',
   'Wait-ThriveLensInterCycleMemorySettle','Assert-ThriveLensConfigurationLease','Get-ThriveLensConfigurationLeaseFingerprint',
   'Assert-ThriveLensWslIdentity','Assert-ThriveLensWslAbsent','Assert-ThriveLensHostPortAbsent','Get-ThriveLensFreeMemoryBytes',
   'Invoke-ThriveLensGuardedDistro','Assert-ThriveLensWslLoopback','Assert-ThriveLensHostLoopback','Invoke-ThriveLensResourceGate'
  )
  $expectedNames=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
  foreach($name in $expected){$null=$expectedNames.Add($name)}
  $observed=@($core.FindAll({param($node)$node -is [Management.Automation.Language.CommandAst] -and $null -ne $node.GetCommandName() -and $expectedNames.Contains($node.GetCommandName())},$true)|Sort-Object {$_.Extent.StartOffset}|ForEach-Object{$_.GetCommandName()})
  if(($observed -join ',') -cne ($expected -join ',')){return $false}
  $coreText=$core.Extent.Text
  if($coreText -match '(?i)pwsh(?:\.exe)?|Start-Process|preflight\.ps1|Get-ThriveLensManifest|1073741824'){return $false}
  foreach($authorityName in @('ConfigurationLease','IdentityToken','LifecycleLock')){
   $authorityAssignments=@($core.FindAll({param($node)$node -is [Management.Automation.Language.AssignmentStatementAst] -and $node.Left.Extent.Text -ceq ('$'+$authorityName)},$true))
   if($authorityAssignments.Count -ne 0){return $false}
  }
  $contractAssignments=@($core.FindAll({param($node)$node -is [Management.Automation.Language.AssignmentStatementAst] -and $node.Left.Extent.Text -ceq '$leasedContract'},$true))
  if($contractAssignments.Count -ne 1){return $false}
  if($coreText -notmatch 'Get-ThriveLensMemoryPolicyThresholds\s+-Manifest\s+\$leasedManifest' -or
     $coreText -notmatch '\$runtimeMinimumBytes\s*=\s*\[int64\]\$memoryPolicy\.RuntimeMinimumBytes' -or
     $coreText -notmatch '\$startReclaimTargetBytes\s*=\s*\[int64\]\$memoryPolicy\.StartReclaimTargetBytes' -or
     $coreText -notmatch '\$activePhase\s*=\s*\[string\]\$leasedResourceBudget\.phase' -or
     $coreText -notmatch 'allowed_active_phases\)\s*-cnotcontains\s+\$activePhase' -or
     $coreText -notmatch 'Get-ThriveLensWslContract\s+-ConfigurationLease\s+\$ConfigurationLease' -or
     $coreText -notmatch 'Get-ThriveLensWslPaths\s+-Contract\s+\$leasedContract'){return $false}
  $memoryGuards=@($core.FindAll({param($node)
   if($node -isnot [Management.Automation.Language.IfStatementAst]){return $false}
   foreach($clause in @($node.Clauses)){if($clause.Item1.Extent.Text -match '^\s*\$freeMemoryBytes\s*-lt\s*\$runtimeMinimumBytes\s*$'){return $true}}
   return $false
  },$true))
  if($memoryGuards.Count -ne 2){return $false}
  $wslFlags=@($core.FindAll({param($node)$node -is [Management.Automation.Language.AssignmentStatementAst] -and $node.Left.Extent.Text -ceq '$WslTouched.Value' -and $node.Right.Extent.Text -ceq '$true'},$true))
  $attemptFlags=@($core.FindAll({param($node)$node -is [Management.Automation.Language.AssignmentStatementAst] -and $node.Left.Extent.Text -ceq '$StartAttempted.Value' -and $node.Right.Extent.Text -ceq '$true'},$true))
  $startAssignments=@($core.FindAll({param($node)$node -is [Management.Automation.Language.AssignmentStatementAst] -and $node.Left.Extent.Text -ceq '$startResult' -and $node.Right.Extent.Text -match '^\s*Invoke-ThriveLensGuardedDistro(?:\s|`)'} ,$true))
  $identityCalls=Get-ThriveLensCommandAsts -Ast $core -Name 'Assert-ThriveLensWslIdentity'
  $terminationCalls=Get-ThriveLensCommandAsts -Ast $core -Name 'Stop-ThriveLensDistroAndVerify'
  $settleCalls=Get-ThriveLensCommandAsts -Ast $core -Name 'Wait-ThriveLensInterCycleMemorySettle'
  $duplicatePathCalls=Get-ThriveLensCommandAsts -Ast $core -Name 'Assert-ThriveLensLinuxPathPolicy'
  $guardedCalls=Get-ThriveLensCommandAsts -Ast $core -Name 'Invoke-ThriveLensGuardedDistro'
  if($wslFlags.Count -ne 1 -or $attemptFlags.Count -ne 1 -or $startAssignments.Count -ne 1 -or
     $identityCalls.Count -ne 2 -or $terminationCalls.Count -ne 1 -or
     $settleCalls.Count -ne 1 -or $duplicatePathCalls.Count -ne 0 -or $guardedCalls.Count -ne 1){return $false}
  $wslGap=$Source.Substring($wslFlags[0].Extent.EndOffset,$identityCalls[0].Extent.StartOffset-$wslFlags[0].Extent.EndOffset)
  $attemptGap=$Source.Substring($attemptFlags[0].Extent.EndOffset,$startAssignments[0].Extent.StartOffset-$attemptFlags[0].Extent.EndOffset)
  if($wslGap -notmatch '^\s*\$null\s*=\s*$' -or -not [string]::IsNullOrWhiteSpace($attemptGap) -or $attemptFlags[0].Extent.StartOffset -gt $guardedCalls[0].Extent.StartOffset){return $false}
  $startTokens=@("'/usr/sbin/runuser'","'-u'","'postgres'","'--'",'$paths.PgCtl',"'start'","'-D'",'$paths.DataRoot',"'-l'","'/dev/null'","'-o'",'$options',"'-w'","'-t'","'30'")
  if(((Get-ArrayArgumentTokenText -Command $guardedCalls[0] -ParameterName 'Arguments')-join "`n") -cne ($startTokens-join "`n")){return $false}
  foreach($boundName in @('Assert-ThriveLensWslIdentity','Assert-ThriveLensWslPackages','Assert-ThriveLensWslInternalDisk','Get-ThriveLensWslClusterState','Assert-ThriveLensWslAbsent','Assert-ThriveLensWslLoopback')){
   foreach($call in @(Get-ThriveLensCommandAsts -Ast $core -Name $boundName)){
    if($call.Extent.Text -notmatch '-Contract\s+\$leasedContract' -or $call.Extent.Text -notmatch '-IdentityToken\s+\$IdentityToken' -or $call.Extent.Text -notmatch '-LifecycleLock\s+\$LifecycleLock'){return $false}
   }
  }
  foreach($hostName in @('Assert-ThriveLensHostPortAbsent','Assert-ThriveLensHostLoopback')){
   foreach($call in @(Get-ThriveLensCommandAsts -Ast $core -Name $hostName)){if($call.Extent.Text -notmatch '-Paths\s+\$paths' -or $call.Extent.Text -notmatch '-Contract\s+\$leasedContract'){return $false}}
  }
  foreach($gate in @(Get-ThriveLensCommandAsts -Ast $core -Name 'Invoke-ThriveLensResourceGate')){if($gate.Extent.Text -notmatch '-Manifest\s+\$leasedManifest'){return $false}}
  if($terminationCalls[0].Extent.Text -notmatch '-IdentityToken\s+\$IdentityToken' -or
     $terminationCalls[0].Extent.Text -notmatch '-LifecycleLock\s+\$LifecycleLock' -or
     $terminationCalls[0].Extent.Text -notmatch '-Contract\s+\$leasedContract' -or
     $settleCalls[0].Extent.Text -notmatch '-MinimumFreeMemoryBytes\s+\$startReclaimTargetBytes' -or
     $identityCalls[1].Extent.Text -notmatch '-IdentityToken\s+\$IdentityToken' -or
     $identityCalls[1].Extent.Text -notmatch '-LifecycleLock\s+\$LifecycleLock' -or
     $identityCalls[1].Extent.Text -notmatch '-Contract\s+\$leasedContract'){return $false}
  $absenceCalls=Get-ThriveLensCommandAsts -Ast $core -Name 'Assert-ThriveLensWslAbsent'
  $hostAbsenceCalls=Get-ThriveLensCommandAsts -Ast $core -Name 'Assert-ThriveLensHostPortAbsent'
  $memoryCalls=Get-ThriveLensCommandAsts -Ast $core -Name 'Get-ThriveLensFreeMemoryBytes'
  $initialSampleThrows=@($core.FindAll({param($node)$node -is [Management.Automation.Language.ThrowStatementAst]},$true)|Where-Object{
   $_.Extent.StartOffset -gt $memoryCalls[0].Extent.StartOffset -and $_.Extent.EndOffset -lt $wslFlags[0].Extent.StartOffset
  })
  $initialMeasurementThrows=@($initialSampleThrows|Where-Object{$_.Extent.Text -ceq "throw 'MEMORY_MEASUREMENT_UNAVAILABLE'"})
  $initialLowMemoryThrows=@($initialSampleThrows|Where-Object{$_.Extent.Text -ceq "throw 'LOW_FREE_MEMORY_AFTER_LIFECYCLE_LOCK'"})
  $commandsAfterFinalMemory=@($core.FindAll({param($node)$node -is [Management.Automation.Language.CommandAst]},$true)|Where-Object{
   $_.Extent.StartOffset -gt $memoryCalls[1].Extent.EndOffset -and $_.Extent.StartOffset -lt $guardedCalls[0].Extent.StartOffset
  })
  $processInvocationAfterFinalMemory=Test-ThriveLensAstHasProcessTypeInvocation -Ast $core -StartOffset $memoryCalls[1].Extent.EndOffset -EndOffset $attemptFlags[0].Extent.StartOffset
  if($absenceCalls.Count -ne 2 -or $hostAbsenceCalls.Count -ne 2 -or $memoryCalls.Count -ne 2 -or
     $initialSampleThrows.Count -ne 4 -or $initialMeasurementThrows.Count -ne 3 -or $initialLowMemoryThrows.Count -ne 1 -or
     $commandsAfterFinalMemory.Count -ne 0 -or $processInvocationAfterFinalMemory -or
     -not ($absenceCalls[0].Extent.StartOffset -lt $hostAbsenceCalls[0].Extent.StartOffset -and
           $hostAbsenceCalls[0].Extent.StartOffset -lt $terminationCalls[0].Extent.StartOffset -and
           $terminationCalls[0].Extent.StartOffset -lt $settleCalls[0].Extent.StartOffset -and
           $settleCalls[0].Extent.StartOffset -lt $identityCalls[1].Extent.StartOffset -and
           $identityCalls[1].Extent.StartOffset -lt $absenceCalls[1].Extent.StartOffset -and
           $absenceCalls[1].Extent.StartOffset -lt $hostAbsenceCalls[1].Extent.StartOffset -and
           $hostAbsenceCalls[1].Extent.StartOffset -lt $memoryCalls[1].Extent.StartOffset -and
           $memoryCalls[1].Extent.StartOffset -lt $attemptFlags[0].Extent.StartOffset)){return $false}
  $postGateFalse=@($core.FindAll({param($node)$node -is [Management.Automation.Language.AssignmentStatementAst] -and $node.Left.Extent.Text -ceq '$StartCommitResourceGateVerified.Value' -and $node.Right.Extent.Text -ceq '$false'},$true))
  $postGateTrue=@($core.FindAll({param($node)$node -is [Management.Automation.Language.AssignmentStatementAst] -and $node.Left.Extent.Text -ceq '$StartCommitResourceGateVerified.Value' -and $node.Right.Extent.Text -ceq '$true'},$true))
  $gates=Get-ThriveLensCommandAsts -Ast $core -Name 'Invoke-ThriveLensResourceGate'
  if($postGateFalse.Count -ne 1 -or $postGateTrue.Count -ne 1 -or $gates.Count -ne 2 -or
     $postGateFalse[0].Extent.StartOffset -gt $gates[0].Extent.StartOffset -or
     $postGateTrue[0].Extent.StartOffset -lt $gates[1].Extent.EndOffset){return $false}
  $postGateGap=$Source.Substring($gates[1].Extent.EndOffset,$postGateTrue[0].Extent.StartOffset-$gates[1].Extent.EndOffset)
  if($postGateGap -notmatch '^\s*\}\s*catch\s*\{[\s\S]*\}\s*$'){return $false}
  return ($guardedCalls[0].Extent.Text -match '-IdentityToken\s+\$IdentityToken' -and $guardedCalls[0].Extent.Text -match '-LifecycleLock\s+\$LifecycleLock' -and $guardedCalls[0].Extent.Text -match '-Contract\s+\$leasedContract' -and $guardedCalls[0].Extent.Text -match '-TimeoutSeconds\s+45')
 }catch{return $false}
}
function Test-ThriveLensWslRunnerContract([string]$Source){
 try{
  $parsed=Get-ThriveLensParsedSource -Source $Source
  if($parsed.Errors.Count -ne 0){return $false}
  $function=Get-ThriveLensFunctionAst -Ast $parsed.Ast -Name 'Invoke-ThriveLensWsl'
  if($null -eq $function){return $false}
  $body=$function.Extent.Text
  return ($body -match '\$timeoutMilliseconds=\[Math\]::BigMul\(\[int\]\$TimeoutSeconds,1000\)' -and
   $body -match '\$stopwatch=\[Diagnostics\.Stopwatch\]::StartNew\(\)' -and $body -notmatch 'DateTime|UtcNow' -and
   @([regex]::Matches($body,'\$timeoutMilliseconds-\$stopwatch\.ElapsedMilliseconds')).Count -eq 2 -and
   $body -match '\$stdinBytes\.Length\s*-gt\s*512' -and $body -match '\[Array\]::Clear\(\$stdinBytes,0,\$stdinBytes\.Length\)' -and
   $body -match '\$stdinWriteTask=\$process\.StandardInput\.BaseStream\.WriteAsync' -and $body -match '\$stdinFlushTask=\$process\.StandardInput\.BaseStream\.FlushAsync' -and
   $body -match '\$failureCode=if\(-not \$started\)\{''WSL_PROCESS_START_FAILED''\}' -and
   $body -match '\$cleanupProven=\$true\s+if\(\$started\)\{' -and
   $body -match 'if\(-not \$process\.HasExited\)\{\$process\.Kill\(\$true\)\}' -and $body -match '\$rootReaped=\$process\.WaitForExit\(5000\)' -and
   $body -match 'if\(\$rootReaped\)\{\$rootReaped=\$process\.HasExited\}' -and
   $body -match 'if\(-not \$rootReaped\)\{\$cleanupProven=\$false\}' -and
   $body -match 'foreach\(\$ioTask in @\(\$stdoutTask,\$stderrTask,\$stdinWriteTask,\$stdinFlushTask\)\)' -and
   $body -match 'if\(\$null -eq \$ioTask\)\{continue\}' -and $body -match '\$ioTask\.Wait\(5000\)' -and
   $body -match 'if\(-not \$ioTask\.IsCompleted\)\{\$cleanupProven=\$false\}' -and
   $body -match 'if\(-not \$cleanupProven\)\{throw ''WSL_OUTPUT_DRAIN_INCOMPLETE''\}' -and
   $body -match 'if\(\$stdoutComplete\)\{\$stdoutSink\.Dispose\(\)\}' -and $body -match 'if\(\$stderrComplete\)\{\$stderrSink\.Dispose\(\)\}' -and
   $body -match 'if\(\$started\)\{try\{\$rootInactive=\$process\.HasExited\}' -and
   $body -match 'if\(\$rootInactive -and \$stdoutComplete -and \$stderrComplete -and \$stdinWriteComplete -and \$stdinFlushComplete\)\{\$process\.Dispose\(\)\}')
 }catch{return $false}
}
function Test-ThriveLensWslSecurityTypeContract([string]$Source){
 try{
  $parsed=Get-ThriveLensParsedSource -Source $Source
  if($parsed.Errors.Count -ne 0){return $false}
  return ($Source -match "\`$wslSecurityTypeNames=@\(\s*'ThriveLens\.WslSecurityV2\.OutputBudget',\s*'ThriveLens\.WslSecurityV2\.BoundedCaptureStream',\s*'ThriveLens\.WslSecurityV2\.HostFileIdentity',\s*'ThriveLens\.WslSecurityV2\.MutexOwnershipVerifier'\s*\)" -and
   @([regex]::Matches($Source,'public const int ContractVersion=2;')).Count -eq 4 -and
   $Source -match '\$existingWslSecurityTypes\.Count\s*-eq\s*0' -and $Source -match '\$existingWslSecurityTypes\.Count\s*-ne\s*\$wslSecurityTypeNames\.Count' -and
   $Source -match '\$versionField\.IsLiteral' -and $Source -match 'GetRawConstantValue\(\)\s*-ne\s*2' -and
   $Source -match '\$attestationBudget=\[ThriveLens\.WslSecurityV2\.OutputBudget\]::new\(8\)' -and
   $Source -match '\$attestationSink\.Length\s*-ne\s*8' -and $Source -match "\(\`$preserved\s*-join\s*','\)\s*-cne\s*'1,2,3,4,5,6,7,8'" -and
   $Source -match 'if\(total>budget\.Limit\)\{budget\.Exceeded=true;throw new IOException\("OUTPUT_LIMIT"\);\}data\.Write\(buffer,offset,count\);')
 }catch{return $false}
}
function Test-ThriveLensStartAdapterContract([string]$Source){
 try{
  $parsed=Get-ThriveLensParsedSource -Source $Source
  if($parsed.Errors.Count -ne 0 -or $Source -match 'Resolve-ThriveLens(?:ChildOutcome|StartChildExit|PreTokenStartObservation|StartChildFailure)' -or $Source -match '(?i)pwsh(?:\.exe)?\s+.*(?:preflight|start)\.ps1|Start-Process|Get-ThriveLensManifest'){return $false}
  $coreCalls=Get-ThriveLensCommandAsts -Ast $parsed.Ast -Name 'Invoke-ThriveLensPostgresStartUnderLock'
  $locks=Get-ThriveLensCommandAsts -Ast $parsed.Ast -Name 'Enter-ThriveLensLifecycleLock'
  $leases=Get-ThriveLensCommandAsts -Ast $parsed.Ast -Name 'Enter-ThriveLensConfigurationLease'
  $contracts=Get-ThriveLensCommandAsts -Ast $parsed.Ast -Name 'Get-ThriveLensWslContract'
  $paths=Get-ThriveLensCommandAsts -Ast $parsed.Ast -Name 'Get-ThriveLensWslPaths'
  $tokens=Get-ThriveLensCommandAsts -Ast $parsed.Ast -Name 'Get-ThriveLensWslCleanupIdentityToken'
  if($coreCalls.Count -ne 1 -or $locks.Count -ne 1 -or $leases.Count -ne 1 -or $contracts.Count -ne 1 -or $paths.Count -ne 1 -or $tokens.Count -ne 1){return $false}
  if(-not ($locks[0].Extent.StartOffset -lt $leases[0].Extent.StartOffset -and $leases[0].Extent.StartOffset -lt $contracts[0].Extent.StartOffset -and
      $contracts[0].Extent.StartOffset -lt $paths[0].Extent.StartOffset -and $paths[0].Extent.StartOffset -lt $tokens[0].Extent.StartOffset -and
      $tokens[0].Extent.StartOffset -lt $coreCalls[0].Extent.StartOffset)){return $false}
  if($contracts[0].Extent.Text -notmatch '-ConfigurationLease\s+\$configurationLease' -or
     $paths[0].Extent.Text -notmatch '-Contract\s+\$leasedContract' -or
     $tokens[0].Extent.Text -notmatch '-Contract\s+\$leasedContract'){return $false}
  if(Test-ThriveLensAstHasAncestor -Node $coreCalls[0] -Type ([Management.Automation.Language.LoopStatementAst]) -Predicate {param($node)$true}){return $false}
  $coreText=$coreCalls[0].Extent.Text
  foreach($binding in @('-ConfigurationLease\s+\$configurationLease','-IdentityToken\s+\$cleanupIdentityToken','-LifecycleLock\s+\$lifecycleLock','-WslTouched\s+\(\[ref\]\$wslTouched\)','-StartAttempted\s+\(\[ref\]\$attempted\)','-StartCommitResourceGateVerified\s+\(\[ref\]\$startCommitResourceGateVerified\)')){if($coreText -notmatch $binding){return $false}}
  if((Get-ThriveLensCommandAsts -Ast $parsed.Ast -Name 'Invoke-ThriveLensGuardedDistro').Count -ne 0){return $false}
  $stops=Get-ThriveLensCommandAsts -Ast $parsed.Ast -Name 'Stop-ThriveLensPostgresUnderLock'
  $forces=Get-ThriveLensCommandAsts -Ast $parsed.Ast -Name 'Stop-ThriveLensDistroAndVerify'
  if($stops.Count -ne 1 -or $forces.Count -ne 1 -or $forces[0].Extent.StartOffset -lt $stops[0].Extent.StartOffset){return $false}
   if($Source -notmatch 'if\s*\(\s*-not\s+\$resourceGateOutputDrainIncomplete\s*-and\s*\$sameTokenAuthority\s*-and\s*\$cleanupLeaseValid\s*-and\s*\$guestCleanupAllowed\s*-and\s*\$attempted\)' -or
     $Source -notmatch 'if\s*\(\$cleanupRequired\s*-and\s*\$null\s*-ne\s*\$lifecycleLock\s*-and\s*\$null\s*-ne\s*\$cleanupIdentityToken\)' -or
     $Source -notmatch 'if\s*\(\$forcedTerminationAuthorized\)'){return $false}
  foreach($cleanupCall in @($stops)+@($forces)){if($cleanupCall.Extent.Text -notmatch '-IdentityToken\s+\$cleanupIdentityToken' -or $cleanupCall.Extent.Text -notmatch '-LifecycleLock\s+\$lifecycleLock' -or $cleanupCall.Extent.Text -notmatch '-Contract\s+\$leasedContract'){return $false}}
  if($stops[0].Extent.Text -notmatch '-Paths\s+\$leasedPaths'){return $false}
  foreach($boundName in @('Assert-ThriveLensWslCleanupIdentity','Assert-ThriveLensDistroStopped')){
   foreach($call in @(Get-ThriveLensCommandAsts -Ast $parsed.Ast -Name $boundName)){if($call.Extent.Text -notmatch '-Contract\s+\$leasedContract'){return $false}}
  }
  foreach($call in @(Get-ThriveLensCommandAsts -Ast $parsed.Ast -Name 'Assert-ThriveLensHostPortAbsent')){
   if($call.Extent.Text -notmatch '-Contract\s+\$leasedContract' -or $call.Extent.Text -notmatch '-Paths\s+\$leasedPaths'){return $false}
  }
  $absenceAssignments=@($parsed.Ast.FindAll({param($node)$node -is [Management.Automation.Language.AssignmentStatementAst] -and $node.Left.Extent.Text -ceq '$absenceObservationAuthorized'},$true))
  $absenceGuards=@($parsed.Ast.FindAll({param($node)
   if($node -isnot [Management.Automation.Language.IfStatementAst]){return $false}
   foreach($clause in @($node.Clauses)){if($clause.Item1.Extent.Text -match '^\s*\$absenceObservationAuthorized\s*$'){return $true}}
   return $false
  },$true))
  $distroAbsenceCalls=Get-ThriveLensCommandAsts -Ast $parsed.Ast -Name 'Assert-ThriveLensDistroStopped'
  $hostAbsenceCalls=Get-ThriveLensCommandAsts -Ast $parsed.Ast -Name 'Assert-ThriveLensHostPortAbsent'
  if($absenceAssignments.Count -ne 1 -or $absenceGuards.Count -ne 1 -or $distroAbsenceCalls.Count -ne 1 -or $hostAbsenceCalls.Count -ne 1 -or
     $absenceAssignments[0].Right.Extent.Text -notmatch '^\s*\$null\s*-ne\s*\$leasedContract\s*-and\s*\$null\s*-ne\s*\$leasedPaths\s*-and\s*\(\s*\$forcedTerminationAuthorized\s*-or\s*-not\s*\$cleanupRequired\s*\)\s*$' -or
     $absenceAssignments[0].Extent.StartOffset -gt $absenceGuards[0].Extent.StartOffset -or
     $distroAbsenceCalls[0].Extent.StartOffset -lt $absenceGuards[0].Extent.StartOffset -or $distroAbsenceCalls[0].Extent.EndOffset -gt $absenceGuards[0].Extent.EndOffset -or
     $hostAbsenceCalls[0].Extent.StartOffset -lt $absenceGuards[0].Extent.StartOffset -or $hostAbsenceCalls[0].Extent.EndOffset -gt $absenceGuards[0].Extent.EndOffset){return $false}
  $adapterGates=Get-ThriveLensCommandAsts -Ast $parsed.Ast -Name 'Invoke-ThriveLensResourceGate'
  if($adapterGates.Count -ne 1 -or $adapterGates[0].Extent.Text -notmatch '-Manifest\s+\$leasedContract\.Manifest' -or
     $forces[0].Extent.StartOffset -gt $adapterGates[0].Extent.StartOffset -or
     $hostAbsenceCalls[0].Extent.StartOffset -gt $adapterGates[0].Extent.StartOffset -or
      $Source -notmatch 'if\s*\(\$attempted\)' -or $Source -notmatch 'if\s*\(\$attempted\)\s*\{\s*\$finalResourceGateVerified\s*=\s*\$false\s*\}' -or
      $Source -notmatch '\$resourceGateOutputDrainIncomplete\s*=\s*\$originalCode\s*-ceq\s*''RESOURCE_GATE_OUTPUT_DRAIN_INCOMPLETE''' -or
      $Source -notmatch 'if\s*\(\$resourceGateOutputDrainIncomplete\)\s*\{[\s\S]*?\$finalResourceGateFailed\s*=\s*\$true\s*\}' -or
      $Source -notmatch '\$cleanupVerified\s*=\s*\$distroAbsent\s*-and\s*\$hostAbsent[\s\S]+?-not\s+\$resourceGateOutputDrainIncomplete' -or
      $Source -notmatch 'if\s*\(\$attempted\s*-and\s*-not\s+\$resourceGateOutputDrainIncomplete\)' -or
     $Source -notmatch 'if\s*\(\$cleanupLeaseValid\s*-and\s*\$null\s*-ne\s*\$leasedContract\)' -or
     $Source -notmatch '\$finalResourceGateFailed\s*=\s*\$true'){return $false}
  $lockFalse=@($parsed.Ast.FindAll({param($node)$node -is [Management.Automation.Language.AssignmentStatementAst] -and $node.Left.Extent.Text -ceq '$lockReleaseFailed' -and $node.Right.Extent.Text -ceq '$false'},$true))
  $leaseFalse=@($parsed.Ast.FindAll({param($node)$node -is [Management.Automation.Language.AssignmentStatementAst] -and $node.Left.Extent.Text -ceq '$leaseReleaseFailed' -and $node.Right.Extent.Text -ceq '$false'},$true))
  $validationAssignments=@($parsed.Ast.FindAll({param($node)$node -is [Management.Automation.Language.AssignmentStatementAst] -and $node.Left.Extent.Text -ceq '$expectedValidationCodes'},$true))
  if($lockFalse.Count -ne 1 -or $leaseFalse.Count -ne 1 -or $validationAssignments.Count -ne 1 -or $validationAssignments[0].Extent.Text -match 'RESOURCE_GATE_OUTPUT_DRAIN_INCOMPLETE'){return $false}
  $leaseExits=Get-ThriveLensCommandAsts -Ast $parsed.Ast -Name 'Exit-ThriveLensConfigurationLease';$lockExits=Get-ThriveLensCommandAsts -Ast $parsed.Ast -Name 'Exit-ThriveLensLifecycleLock'
  if($leaseExits.Count -ne 2 -or $lockExits.Count -ne 2){return $false}
  $successAssert=$Source.IndexOf('Assert-ThriveLensConfigurationLease -Lease $configurationLease',$coreCalls[0].Extent.EndOffset,[StringComparison]::Ordinal)
  $successLeaseAttempt=$Source.IndexOf('$leaseReleaseAttempted = $true',$successAssert,[StringComparison]::Ordinal)
  $successLease=$leaseExits[0].Extent.StartOffset;$successLeaseReleased=$Source.IndexOf('$leaseReleased = $true',$successLease,[StringComparison]::Ordinal)
  $successLeaseClear=$Source.IndexOf('$configurationLease = $null',$successLeaseReleased,[StringComparison]::Ordinal)
  $successLockAttempt=$Source.IndexOf('$lockReleaseAttempted = $true',$successLeaseClear,[StringComparison]::Ordinal)
  $successLock=$lockExits[0].Extent.StartOffset;$successLockReleased=$Source.IndexOf('$lockReleased = $true',$successLock,[StringComparison]::Ordinal)
  $successTokenClear=$Source.IndexOf('$cleanupIdentityToken = $null',$successLockReleased,[StringComparison]::Ordinal)
  $startedResponse=$Source.IndexOf("status = 'STARTED'",$successTokenClear,[StringComparison]::Ordinal)
  if(-not ($successAssert -gt $coreCalls[0].Extent.EndOffset -and $successAssert -lt $successLeaseAttempt -and $successLeaseAttempt -lt $successLease -and $successLease -lt $successLeaseReleased -and $successLeaseReleased -lt $successLeaseClear -and $successLeaseClear -lt $successLockAttempt -and $successLockAttempt -lt $successLock -and $successLock -lt $successLockReleased -and $successLockReleased -lt $successTokenClear -and $successTokenClear -lt $startedResponse)){return $false}
  if($adapterGates[0].Extent.StartOffset -gt $leaseExits[1].Extent.StartOffset -or $leaseExits[1].Extent.StartOffset -gt $lockExits[1].Extent.StartOffset -or
     $Source -notmatch 'if\s*\(\$null\s*-ne\s*\$configurationLease\s*-and\s*-not\s+\$leaseReleaseAttempted\)' -or
     $Source -notmatch 'if\s*\(\$null\s*-ne\s*\$lifecycleLock\s*-and\s*-not\s+\$lockReleaseAttempted\)'){return $false}
  return ($Source -match '\$fatal\s*=\s*\$startSucceeded\s*-or\s*\$attempted' -and
   $Source -match "'RESOURCE_GATE_FAILED'[\s\S]+?'RESOURCE_GATE_UNAVAILABLE'[\s\S]+?'RESOURCE_GATE_RESULT_INVALID'[\s\S]+?'RESOURCE_GATE_MANIFEST_INVALID'[\s\S]+?'RESOURCE_GATE_PROCESS_START_FAILED'[\s\S]+?'RESOURCE_GATE_TIMEOUT'[\s\S]+?'RESOURCE_GATE_OUTPUT_LIMIT'[\s\S]+?'WSL_STANDARD_INPUT_INVALID'[\s\S]+?'WSL_STANDARD_INPUT_LIMIT_EXCEEDED'" -and
   $Source -match 'port\s*=\s*\[int\]\$leasedPaths\.Port' -and $Source -notmatch 'port\s*=\s*55432' -and
   $Source -match 'if\s*\(\$resourceGateOutputDrainIncomplete\s*-and\s*-not\s+\$attempted\)[\s\S]+RESOURCE_GATE_OUTPUT_DRAIN_INCOMPLETE[\s\S]+elseif\s*\(\$finalResourceGateFailed\)[\s\S]+POST_MUTATION_RESOURCE_GATE_FAILED[\s\S]+elseif\s*\(\$lockReleaseFailed\)' -and
   $Source -match '\$lockReleaseFailed\s*-or\s*\$leaseReleaseFailed' -and
   $Source -match 'elseif \(\$lockReleaseFailed\)[\s\S]+POSTGRES_START_LOCK_RELEASE_FAILED[\s\S]+elseif \(\$leaseReleaseFailed\)[\s\S]+POSTGRES_START_CONFIGURATION_LEASE_RELEASE_FAILED' -and
   $Source -match 'guest_cleanup_attempted\s*=\s*\$guestCleanupAttempted' -and
   $Source -match 'forced_termination_attempted\s*=\s*\$forcedTerminationAttempted' -and
   $Source -match 'configuration_lease_release_attempted\s*=\s*\$leaseReleaseAttempted' -and
   $Source -match 'lifecycle_lock_release_attempted\s*=\s*\$lockReleaseAttempted' -and
   $Source -match 'post_mutation_resource_gate_verified\s*=\s*\$finalResourceGateVerified\s*-and\s*-not\s*\$finalResourceGateFailed')
 }catch{return $false}
}
function Test-ThriveLensInterCyclePolicyContract([string]$Source){
 try{
  $parsed=Get-ThriveLensParsedSource -Source $Source
  if($parsed.Errors.Count -ne 0){return $false}
  $helper=Get-ThriveLensFunctionAst -Ast $parsed.Ast -Name 'Get-ThriveLensInterCycleMemoryTargetBytes'
  if($null -eq $helper){return $false}
  $parameters=@($helper.Body.ParamBlock.Parameters|ForEach-Object{$_.Name.VariablePath.UserPath})
  if(($parameters -join ',') -cne 'Manifest'){return $false}
  $body=$helper.Extent.Text
  return ($body -notmatch '(?i)WSL|Get-ThriveLensManifest|Invoke-|Start-|Stop-|Remove-|Set-' -and
   $body -match "'runtime_minimum_free_memory_bytes'\s*,\s*'install_minimum_free_memory_bytes'" -and
   $body -match '\$policyValues\.Count\s*-ne\s*1' -and
   $body -match '\$candidateValues\.Count\s*-ne\s*1' -and
   $body -match '\$candidateValues\[0\]\s*-isnot\s*\[int64\]' -and
   $body -notmatch 'TryParse|Convert\]::ToString' -and $body -match '\$candidateBytes\s*-le\s*0' -and
   $body -match 'return\s+\[Math\]::Max\(\$validatedValues\[0\],\s*\$validatedValues\[1\]\)' -and
   $body -match "throw\s+'RUNTIME_MEMORY_POLICY_INVALID'")
 }catch{return $false}
}
function Test-ThriveLensMemoryPolicyContract([string]$Source){
 try{
  $parsed=Get-ThriveLensParsedSource -Source $Source
  if($parsed.Errors.Count -ne 0){return $false}
  $helper=Get-ThriveLensFunctionAst -Ast $parsed.Ast -Name 'Get-ThriveLensMemoryPolicyThresholds'
  if($null -eq $helper){return $false}
  $body=$helper.Extent.Text
  return ($body -notmatch '(?i)WSL|Get-ThriveLensManifest|Invoke-|Start-|Stop-|Remove-|Set-' -and
   $body -match "'runtime_minimum_free_memory_bytes'\s*,\s*'install_minimum_free_memory_bytes'" -and
   $body -match '\$policyValues\.Count\s*-ne\s*1' -and $body -match '\[object\[\]\]\$candidateValues\s*=' -and $body -match '\$candidateValues\.Count\s*-ne\s*1' -and
   $body -match '\$candidateValues\[0\]\s*-isnot\s*\[int64\]' -and $body -notmatch 'TryParse|Convert\]::ToString' -and
   $body -match '\$candidateBytes\s*-le\s*0' -and
   $body -match 'RuntimeMinimumBytes\s*=\s*\[int64\]\$validatedValues\[0\]' -and
   $body -match 'InstallMinimumBytes\s*=\s*\[int64\]\$validatedValues\[1\]' -and
   $body -match 'StartReclaimTargetBytes\s*=\s*\[int64\]\[Math\]::Max\(\$validatedValues\[0\],\s*\$validatedValues\[1\]\)' -and
   $body -match "throw\s+'RUNTIME_MEMORY_POLICY_INVALID'")
 }catch{return $false}
}
function Test-ThriveLensPreflightWiringContract([string]$Source){
 try{
  $parsed=Get-ThriveLensParsedSource -Source $Source;if($parsed.Errors.Count -ne 0){return $false}
  $calls=Get-ThriveLensCommandAsts -Ast $parsed.Ast -Name 'Complete-ThriveLensPreflightProbeAndAdmit'
  if($calls.Count -ne 1 -or $calls[0].Extent.Text -notmatch '-IdentityToken\s+\$cleanupIdentityToken' -or $calls[0].Extent.Text -notmatch '-LifecycleLock\s+\$preflightLock' -or $calls[0].Extent.Text -notmatch '-MinimumFreeMemoryBytes\s+\$minimum'){return $false}
  $ready=$Source.LastIndexOf("status='READY'",[StringComparison]::Ordinal);if($ready -lt $calls[0].Extent.EndOffset){return $false}
  return ($Source -match '\$postProbeCode\s*-cin\s*@\(' -and
   $Source -match "'LOW_FREE_MEMORY_AFTER_WSL_PROBES','MEMORY_MEASUREMENT_UNAVAILABLE_AFTER_WSL_PROBES'" -and
   $Source -match '\$blockers\.Add\(\$postProbeCode\)' -and $Source -match 'status\s*=\s*''BLOCKED''[\s\S]+exit 2' -and
   $Source -match 'status\s*=\s*''ERROR'';\s*action\s*=\s*\$Action;\s*codes\s*=\s*@\(''PREFLIGHT_DISTRO_CLEANUP_FAILED''\)' -and
   $Source -match 'PREFLIGHT_DISTRO_CLEANUP_FAILED[\s\S]+exit 3')
 }catch{return $false}
}
function Test-ThriveLensRuntimeAdapterContract([string]$Source){
 try{
  $parsed=Get-ThriveLensParsedSource -Source $Source
  if($parsed.Errors.Count -ne 0 -or $Source -match 'Resolve-ThriveLens(?:ChildOutcome|StartChildExit|PreTokenStartObservation|StartChildFailure)' -or $Source -match '(?i)pwsh(?:\.exe)?\s+.*(?:preflight|start|stop)\.ps1|Start-Process|Get-ThriveLensManifest'){return $false}
  $cycles=@($parsed.Ast.FindAll({param($node)$node -is [Management.Automation.Language.ForEachStatementAst] -and $node.Variable.VariablePath.UserPath -ceq 'cycle' -and $node.Condition.Extent.Text -match '^\s*1\s*\.\.\s*2\s*$'},$true))
  $cores=Get-ThriveLensCommandAsts -Ast $parsed.Ast -Name 'Invoke-ThriveLensPostgresStartUnderLock'
  $contracts=Get-ThriveLensCommandAsts -Ast $parsed.Ast -Name 'Get-ThriveLensWslContract'
  $paths=Get-ThriveLensCommandAsts -Ast $parsed.Ast -Name 'Get-ThriveLensWslPaths'
  $tokens=Get-ThriveLensCommandAsts -Ast $parsed.Ast -Name 'Get-ThriveLensWslCleanupIdentityToken'
  $targets=Get-ThriveLensCommandAsts -Ast $parsed.Ast -Name 'Get-ThriveLensInterCycleMemoryTargetBytes'
  $settles=Get-ThriveLensCommandAsts -Ast $parsed.Ast -Name 'Wait-ThriveLensInterCycleMemorySettle'
  if($cycles.Count -ne 1 -or $cores.Count -ne 1 -or $contracts.Count -ne 1 -or $paths.Count -ne 1 -or $tokens.Count -ne 1 -or $targets.Count -ne 1 -or $settles.Count -ne 1 -or
     -not (Test-ThriveLensInterCyclePolicyContract -Source $Source)){return $false}
  $cycle=$cycles[0]
  foreach($call in @($cores)+@($contracts)+@($paths)+@($tokens)){if($call.Extent.StartOffset -le $cycle.Extent.StartOffset -or $call.Extent.EndOffset -ge $cycle.Extent.EndOffset){return $false}}
  $lockIndex=$Source.IndexOf('$probeLifecycleLock = Enter-ThriveLensLifecycleLock',$cycle.Extent.StartOffset,[StringComparison]::Ordinal)
  $leaseIndex=$Source.IndexOf('$configurationLease = Enter-ThriveLensConfigurationLease',$lockIndex,[StringComparison]::Ordinal)
  $contractIndex=$contracts[0].Extent.StartOffset;$pathsIndex=$paths[0].Extent.StartOffset;$tokenIndex=$tokens[0].Extent.StartOffset;$coreIndex=$cores[0].Extent.StartOffset
  if($cores[0].Extent.Text -notmatch '-StartCommitResourceGateVerified\s+\(\[ref\]\$startCommitResourceGateVerified\)'){return $false}
  $firstProbe=$Source.IndexOf('Assert-ThriveLensClusterScramConfig',$coreIndex,[StringComparison]::Ordinal)
  $identityProbe=$Source.IndexOf('Get-ThriveLensPrivateClusterIdentityFingerprint',$firstProbe,[StringComparison]::Ordinal)
  $successStop=$Source.IndexOf('Stop-ThriveLensPostgresUnderLock -IdentityToken $probeIdentityToken',$firstProbe,[StringComparison]::Ordinal)
  $successForce=$Source.IndexOf('Stop-ThriveLensDistroAndVerify -IdentityToken $probeIdentityToken',$successStop,[StringComparison]::Ordinal)
  $successDistroAbsence=$Source.IndexOf('Assert-ThriveLensDistroStopped -Contract $leasedContract',$successForce,[StringComparison]::Ordinal)
  $successHostAbsence=$Source.IndexOf('Assert-ThriveLensHostPortAbsent -Paths $leasedPaths -Contract $leasedContract',$successDistroAbsence,[StringComparison]::Ordinal)
  $successFinalGate=$Source.IndexOf('Invoke-ThriveLensResourceGate -Manifest $manifest',$successHostAbsence,[StringComparison]::Ordinal)
  $completed=$Source.IndexOf('$completedCycles++',$successForce,[StringComparison]::Ordinal)
  $target=$targets[0].Extent.StartOffset
  $releaseLease=$Source.IndexOf('Exit-ThriveLensConfigurationLease -Lease $configurationLease',$target,[StringComparison]::Ordinal)
  $clearLease=$Source.IndexOf('$configurationLease = $null',$releaseLease,[StringComparison]::Ordinal)
  $releaseLock=$Source.IndexOf('Exit-ThriveLensLifecycleLock -Mutex $probeLifecycleLock',$clearLease,[StringComparison]::Ordinal)
  $clearToken=$Source.IndexOf('$probeIdentityToken = $null',$releaseLock,[StringComparison]::Ordinal)
  $clearContract=$Source.IndexOf('$leasedContract = $null',$clearToken,[StringComparison]::Ordinal)
  $clearPaths=$Source.IndexOf('$leasedPaths = $null',$clearContract,[StringComparison]::Ordinal)
  $clearManifest=$Source.IndexOf('$manifest = $null',$clearPaths,[StringComparison]::Ordinal)
  $settle=$settles[0].Extent.StartOffset
  $continue=$Source.IndexOf('continue',$settles[0].Extent.EndOffset,[StringComparison]::Ordinal)
  $postSettleCommands=@($cycle.FindAll({param($node)$node -is [Management.Automation.Language.CommandAst]},$true)|Where-Object{$_.Extent.StartOffset -ge $settles[0].Extent.EndOffset -and $_.Extent.EndOffset -le $continue})
  if(-not ($lockIndex -ge 0 -and $lockIndex -lt $leaseIndex -and $leaseIndex -lt $contractIndex -and $contractIndex -lt $pathsIndex -and $pathsIndex -lt $tokenIndex -and $tokenIndex -lt $coreIndex -and $coreIndex -lt $firstProbe -and $firstProbe -lt $identityProbe -and $identityProbe -lt $successStop -and $successStop -lt $successForce -and $successForce -lt $successDistroAbsence -and $successDistroAbsence -lt $successHostAbsence -and $successHostAbsence -lt $successFinalGate -and $successFinalGate -lt $completed -and $completed -lt $target -and $target -lt $releaseLease -and $releaseLease -lt $clearLease -and $clearLease -lt $releaseLock -and $releaseLock -lt $clearToken -and $clearToken -lt $clearContract -and $clearContract -lt $clearPaths -and $clearPaths -lt $clearManifest -and $clearManifest -lt $settle -and $settle -lt $continue -and $continue -lt $cycle.Extent.EndOffset -and $postSettleCommands.Count -eq 0)){return $false}
  if($contracts[0].Extent.Text -notmatch '-ConfigurationLease\s+\$configurationLease' -or
     $paths[0].Extent.Text -notmatch '-Contract\s+\$leasedContract' -or
     $tokens[0].Extent.Text -notmatch '-Contract\s+\$leasedContract' -or
     $Source -notmatch '\$manifest\s*=\s*\$leasedContract\.Manifest' -or
     $targets[0].Extent.Text -notmatch '-Manifest\s+\$manifest' -or
     $settles[0].Extent.Text -notmatch '-MinimumFreeMemoryBytes\s+\$interCycleMemoryTargetBytes' -or
     $Source -match '\$interCycleMemoryTargetBytes\s*=\s*(?:\[int64\])?(?:1073741824|2147483648)'){return $false}
  foreach($call in @(Get-ThriveLensCommandAsts -Ast $cycle -Name 'Assert-ThriveLensWslCleanupIdentity')){
   if($call.Extent.Text -notmatch '-IdentityToken\s+\$probeIdentityToken' -or $call.Extent.Text -notmatch '-LifecycleLock\s+\$probeLifecycleLock' -or $call.Extent.Text -notmatch '-Contract\s+\$leasedContract'){return $false}
  }
  foreach($boundName in @('Assert-ThriveLensClusterScramConfig','Assert-ThriveLensWslLoopback')){
   foreach($call in @(Get-ThriveLensCommandAsts -Ast $cycle -Name $boundName)){if($call.Extent.Text -notmatch '-Paths\s+\$leasedPaths' -or $call.Extent.Text -notmatch '-Contract\s+\$leasedContract' -or $call.Extent.Text -notmatch '-IdentityToken\s+\$probeIdentityToken' -or $call.Extent.Text -notmatch '-LifecycleLock\s+\$probeLifecycleLock'){return $false}}
  }
  foreach($call in @(Get-ThriveLensCommandAsts -Ast $cycle -Name 'Assert-ThriveLensHostLoopback')){if($call.Extent.Text -notmatch '-Paths\s+\$leasedPaths' -or $call.Extent.Text -notmatch '-Contract\s+\$leasedContract'){return $false}}
  foreach($call in @(Get-ThriveLensCommandAsts -Ast $cycle -Name 'Assert-ThriveLensAuthenticatedScalar')+@(Get-ThriveLensCommandAsts -Ast $cycle -Name 'Remove-ThriveLensRuntimeCredential')){
   if($call.Extent.Text -notmatch '-Contract\s+\$leasedContract' -or $call.Extent.Text -notmatch '-Paths\s+\$leasedPaths' -or $call.Extent.Text -notmatch '-IdentityToken\s+\$probeIdentityToken' -or $call.Extent.Text -notmatch '-LifecycleLock\s+\$probeLifecycleLock'){return $false}
  }
  foreach($call in @(Get-ThriveLensCommandAsts -Ast $cycle -Name 'Invoke-ThriveLensGuardedDistro')){if($call.Extent.Text -notmatch '-Contract\s+\$leasedContract' -or $call.Extent.Text -notmatch '-IdentityToken\s+\$probeIdentityToken' -or $call.Extent.Text -notmatch '-LifecycleLock\s+\$probeLifecycleLock'){return $false}}
  foreach($call in @(Get-ThriveLensCommandAsts -Ast $cycle -Name 'Stop-ThriveLensPostgresUnderLock')){if($call.Extent.Text -notmatch '-Contract\s+\$leasedContract' -or $call.Extent.Text -notmatch '-Paths\s+\$leasedPaths'){return $false}}
  foreach($call in @(Get-ThriveLensCommandAsts -Ast $cycle -Name 'Stop-ThriveLensDistroAndVerify')+@(Get-ThriveLensCommandAsts -Ast $cycle -Name 'Assert-ThriveLensDistroStopped')){if($call.Extent.Text -notmatch '-Contract\s+\$leasedContract'){return $false}}
  foreach($call in @(Get-ThriveLensCommandAsts -Ast $cycle -Name 'Assert-ThriveLensHostPortAbsent')){if($call.Extent.Text -notmatch '-Paths\s+\$leasedPaths' -or $call.Extent.Text -notmatch '-Contract\s+\$leasedContract'){return $false}}
  $identityProbeCalls=Get-ThriveLensCommandAsts -Ast $cycle -Name 'Get-ThriveLensPrivateClusterIdentityFingerprint'
  if($identityProbeCalls.Count -ne 1 -or $identityProbeCalls[0].Extent.Text -notmatch '-IdentityToken\s+\$probeIdentityToken' -or
     $identityProbeCalls[0].Extent.Text -notmatch '-LifecycleLock\s+\$probeLifecycleLock' -or
     $identityProbeCalls[0].Extent.Text -notmatch '-Contract\s+\$leasedContract' -or
     $identityProbeCalls[0].Extent.Text -notmatch '-Paths\s+\$leasedPaths'){return $false}
  $identityFunctions=@($parsed.Ast.FindAll({param($node)$node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq 'Get-ThriveLensPrivateClusterIdentityFingerprint'},$true))
  if($identityFunctions.Count -ne 1){return $false}
  $identityBody=$identityFunctions[0].Extent.Text
  if($identityBody -notmatch 'Invoke-ThriveLensGuardedDistro[\s\S]+-CapturePrivateStandardError[\s\S]+\$Paths\.PgControlData,\s*\$Paths\.DataRoot' -or
     $identityBody -notmatch "'/usr/bin/env',\s*'-i',\s*'LC_ALL=C',\s*'LANG=C'" -or
     $identityBody -notmatch 'Database system identifier' -or $identityBody -notmatch '\[uint64\]::TryParse' -or
     $identityBody -notmatch 'SHA256\]::HashData' -or $identityBody -match 'Write-(?:Output|Host|Error|Warning|Information)' -or
      $identityBody -match 'return\s+\$identifier(?:Text)?\b'){return $false}
   if($Source -notmatch 'elseif\s*\(\$cycleClusterIdentityFingerprint\s*-cne\s*\$clusterIdentityFingerprint\)\s*\{\s*throw\s+''POSTGRES_SYSTEM_IDENTIFIER_INVALID''\s*\}') {return $false}
  if($Source -notmatch '\$completedCycles\s*-ne\s*2' -or $Source -notmatch 'real_postgresql\s*=\s*\(\$completedCycles\s*-eq\s*2\)' -or $Source -notmatch 'cycles\s*=\s*\$completedCycles' -or
     $Source -notmatch '\$proofCounts\.ScramAuthenticated\s*-ne\s*2' -or $Source -notmatch '\$proofCounts\.HostAbsenceVerified\s*-ne\s*2' -or
     $Source -notmatch '\$proofCounts\.ClusterIdentityProbed\s*-ne\s*2' -or $Source -notmatch '\$proofCounts\.PostMutationResourceGateVerified\s*-ne\s*2' -or
     $Source -notmatch 'same_cluster_identity_verified\s*=\s*\$sameClusterIdentityVerified\s*-and\s*\(\$proofCounts\.ClusterIdentityProbed\s*-eq\s*2\)' -or
     $Source -notmatch 'post_mutation_resource_gate_verified\s*=\s*\(\$proofCounts\.PostMutationResourceGateVerified\s*-eq\s*2\)' -or
     $Source -notmatch 'if\s*\(\s*-not\s+\$cycleComplete\s*\)\s*\{\s*throw\s+''RUNTIME_TEST_INTERNAL_ERROR'''){return $false}
  if($Source -notmatch 'if \(\$cycle -eq 1\)[\s\S]+credentialAbsenceVerified[\s\S]+Wait-ThriveLensInterCycleMemorySettle[\s\S]+continue'){return $false}
  $lockFalse=@($parsed.Ast.FindAll({param($node)$node -is [Management.Automation.Language.AssignmentStatementAst] -and $node.Left.Extent.Text -ceq '$lockReleaseFailed' -and $node.Right.Extent.Text -ceq '$false'},$true))
  $leaseFalse=@($parsed.Ast.FindAll({param($node)$node -is [Management.Automation.Language.AssignmentStatementAst] -and $node.Left.Extent.Text -ceq '$leaseReleaseFailed' -and $node.Right.Extent.Text -ceq '$false'},$true))
  if($lockFalse.Count -ne 1 -or $leaseFalse.Count -ne 1){return $false}
  $catchStop=$Source.IndexOf('Stop-ThriveLensPostgresUnderLock -IdentityToken $probeIdentityToken',$cycle.Extent.EndOffset,[StringComparison]::Ordinal)
  $catchForce=$Source.IndexOf('Stop-ThriveLensDistroAndVerify -IdentityToken $probeIdentityToken',$catchStop,[StringComparison]::Ordinal)
  $catchDistroAbsence=$Source.IndexOf('Assert-ThriveLensDistroStopped -Contract $leasedContract',$catchForce,[StringComparison]::Ordinal)
  $catchHostAbsence=$Source.IndexOf('Assert-ThriveLensHostPortAbsent -Paths $leasedPaths -Contract $leasedContract',$catchDistroAbsence,[StringComparison]::Ordinal)
  $catchFinalGate=$Source.IndexOf('Invoke-ThriveLensResourceGate -Manifest $leasedContract.Manifest',$catchHostAbsence,[StringComparison]::Ordinal)
  $catchToken=$Source.IndexOf('Get-ThriveLensWslCleanupIdentityToken',$cycle.Extent.EndOffset,[StringComparison]::Ordinal)
  $catchLeaseRelease=$Source.IndexOf('Exit-ThriveLensConfigurationLease -Lease $configurationLease',$cycle.Extent.EndOffset,[StringComparison]::Ordinal)
  $catchLockRelease=$Source.IndexOf('Exit-ThriveLensLifecycleLock -Mutex $probeLifecycleLock',$catchLeaseRelease,[StringComparison]::Ordinal)
  return ($catchStop -gt $cycle.Extent.EndOffset -and $catchForce -gt $catchStop -and $catchToken -lt 0 -and
   $catchDistroAbsence -gt $catchForce -and $catchHostAbsence -gt $catchDistroAbsence -and $catchFinalGate -gt $catchHostAbsence -and
   $catchLeaseRelease -gt $catchFinalGate -and $catchLockRelease -gt $catchLeaseRelease -and
   $Source -match '\$coreAttemptFailed\s*=\s*\$attempted\s*-and\s*-not\s*\$started' -and
   $Source -match '\$originalExitCode\s*=\s*if\([\s\S]+\$coreAttemptFailed[\s\S]+\)\{3\}else\{2\}' -and
   $Source -match 'if\(\$attempted\)\{\$finalResourceGateVerified=\$false\}' -and
    $Source -match '\$resourceGateOutputDrainIncomplete\s*=\s*\$rawFailureCode\s*-ceq\s*''RESOURCE_GATE_OUTPUT_DRAIN_INCOMPLETE''\s*-or\s*\$originalCode\s*-ceq\s*''RESOURCE_GATE_OUTPUT_DRAIN_INCOMPLETE''' -and
    $Source -match 'if\(\$resourceGateOutputDrainIncomplete\)\{[\s\S]*?\$finalResourceGateFailed=\$true\s*\}' -and
    $Source -match 'if\(\$attempted\s*-and\s*-not\s+\$resourceGateOutputDrainIncomplete\)\{[\s\S]+Invoke-ThriveLensResourceGate\s+-Manifest\s+\$leasedContract\.Manifest' -and
    $Source -match 'if\(\s*-not\s+\$resourceGateOutputDrainIncomplete\s*-and\s*\$cleanupLeaseVerified\s*-and\s*\$cleanupIdentityVerified\s*-and\s*\$guestCleanupAllowed\s*-and\s*\$attempted\)' -and
   $Source -match 'Forced exact-distro containment is independent of lease validity' -and
   $Source -match 'if\(\$null\s*-ne\s*\$configurationLease\s*-and\s*-not\s+\$currentLeaseReleaseAttempted\)' -and
    $Source -match 'if\(\$resourceGateOutputDrainIncomplete\)\{\s*\$finalStatus=''ERROR''[\s\S]+?\$finalCode=if\(\$attempted\)\{''POST_MUTATION_RESOURCE_GATE_FAILED''\}else\{''RESOURCE_GATE_OUTPUT_DRAIN_INCOMPLETE''\}[\s\S]+?\$finalExitCode=3\s*\}' -and
    $Source -match 'cleanup_verified\s*=\s*\[bool\]\$outcome\.CleanupVerified\s*-and\s*-not\s+\$resourceGateOutputDrainIncomplete' -and
    $Source -match 'if\(\$null\s*-ne\s*\$probeLifecycleLock\s*-and\s*-not\s+\$currentLockReleaseAttempted\)')
 }catch{return $false}
}
function Invoke-ThriveLensStartCoreHarness([string]$Definition,[string]$Mode){
 $module=New-Module -ArgumentList $Definition -ScriptBlock {
  param([string]$CoreDefinition)
  $script:Mode='SUCCESS';$script:Log=[Collections.Generic.List[string]]::new();$script:LeaseAssertCalls=0;$script:ResourceCalls=0;$script:MemoryCalls=0;$script:ExpectedLease=$null;$script:ExpectedToken=$null;$script:ExpectedLock=$null;$script:ExpectedContract=$null
  function Add-CoreLog([string]$Name){$null=$script:Log.Add($Name)}
  function Test-CoreAuthority($ConfigurationLease=$null,$IdentityToken=$null,$LifecycleLock=$null,$Contract=$null){if($null -ne $ConfigurationLease -and -not [object]::ReferenceEquals($ConfigurationLease,$script:ExpectedLease)){throw 'SYNTHETIC_LEASE_CHANGED'};if($null -ne $IdentityToken -and -not [object]::ReferenceEquals($IdentityToken,$script:ExpectedToken)){throw 'SYNTHETIC_TOKEN_CHANGED'};if($null -ne $LifecycleLock -and -not [object]::ReferenceEquals($LifecycleLock,$script:ExpectedLock)){throw 'SYNTHETIC_LOCK_CHANGED'};if($null -ne $Contract -and -not [object]::ReferenceEquals($Contract,$script:ExpectedContract)){throw 'SYNTHETIC_CONTRACT_CHANGED'}}
  function Assert-ThriveLensLifecycleLockOwnership {param($LifecycleLock)Test-CoreAuthority -LifecycleLock $LifecycleLock;Add-CoreLog 'LOCK'}
  function Assert-ThriveLensConfigurationLease {param($Lease)Test-CoreAuthority -ConfigurationLease $Lease;Add-CoreLog 'LEASE_ASSERT';$script:LeaseAssertCalls++;if($script:Mode -ceq 'COMMIT_LEASE_FAIL' -and $script:LeaseAssertCalls -eq 2){throw 'CONFIGURATION_LEASE_CONTENT_CHANGED'}}
  function Get-ThriveLensConfigurationLeaseFingerprint {param($Lease)Add-CoreLog 'FINGERPRINT';if($script:Mode -ceq 'COMMIT_FINGERPRINT_FAIL' -and $script:LeaseAssertCalls -ge 2){return 'B'};return 'A'}
  function Get-ThriveLensLeasedResourceBudget {param($Lease)Add-CoreLog 'LEASE_RESOURCE';return [pscustomobject]@{phase='bootstrap_active'}}
  function Get-ThriveLensWslContract {param($ConfigurationLease)Test-CoreAuthority -ConfigurationLease $ConfigurationLease;Add-CoreLog 'LEASE_CONTRACT';$script:ExpectedContract=[pscustomobject]@{Manifest=[pscustomobject]@{resource_policy=[pscustomobject]@{allowed_active_phases=@('bootstrap_active');runtime_minimum_free_memory_bytes=[int64]1024;install_minimum_free_memory_bytes=[int64]2048}};Wsl=[pscustomobject]@{}};return $script:ExpectedContract}
  function Invoke-ThriveLensResourceGate {param($Manifest)Add-CoreLog 'RESOURCE';$script:ResourceCalls++;if($script:Mode -ceq 'EARLY_RESOURCE' -and $script:ResourceCalls -eq 1){throw 'SYNTHETIC'};if($script:Mode -ceq 'POST_GATE' -and $script:ResourceCalls -eq 2){throw 'SYNTHETIC'}}
  function Get-ThriveLensMemoryPolicyThresholds {param($Manifest)Add-CoreLog 'MEMORY_POLICY';return [pscustomobject]@{RuntimeMinimumBytes=[int64]1024;InstallMinimumBytes=[int64]2048;StartReclaimTargetBytes=[int64]2048}}
  function Get-ThriveLensFreeMemoryBytes {Add-CoreLog 'RAM';$script:MemoryCalls++;if($script:Mode -ceq 'RAM1_LOW' -and $script:MemoryCalls -eq 1){return 1023};if($script:Mode -ceq 'RAM1_INVALID' -and $script:MemoryCalls -eq 1){return 'invalid'};if($script:Mode -ceq 'RAM2_LOW' -and $script:MemoryCalls -eq 2){return 1023};if($script:Mode -ceq 'RAM2_INVALID' -and $script:MemoryCalls -eq 2){return 'invalid'};return 2048}
  function Assert-ThriveLensWslIdentity {param($IdentityToken,$LifecycleLock,$Contract)Test-CoreAuthority -IdentityToken $IdentityToken -LifecycleLock $LifecycleLock -Contract $Contract;Add-CoreLog 'WSL_IDENTITY'}
  function Assert-ThriveLensWslPackages {param($Contract,$IdentityToken,$LifecycleLock)Add-CoreLog 'PACKAGES';if($script:Mode -ceq 'MID_PACKAGES'){throw 'WSL_PACKAGE_MISMATCH'}}
  function Assert-ThriveLensWslInternalDisk {param($RequiredBytes,$Contract,$IdentityToken,$LifecycleLock)Add-CoreLog 'DISK'}
  function Get-ThriveLensWslClusterState {param($Paths,$Contract,$IdentityToken,$LifecycleLock)Add-CoreLog 'CLUSTER';return 'VALID'}
  function Assert-ThriveLensWslAbsent {param($Paths,$Contract,$IdentityToken,$LifecycleLock)Add-CoreLog 'WSL_ABSENT'}
  function Assert-ThriveLensHostPortAbsent {param($Paths,$Contract)Add-CoreLog 'HOST_ABSENT'}
  function Stop-ThriveLensDistroAndVerify {param($IdentityToken,$LifecycleLock,$Contract)Test-CoreAuthority -IdentityToken $IdentityToken -LifecycleLock $LifecycleLock -Contract $Contract;Add-CoreLog 'TERMINATE'}
  function Wait-ThriveLensInterCycleMemorySettle {param($MinimumFreeMemoryBytes)Add-CoreLog ("SETTLE:$MinimumFreeMemoryBytes");if($script:Mode -ceq 'SETTLE_LOW'){throw 'RESOURCE_INTER_CYCLE_MEMORY_NOT_SETTLED'};if($script:Mode -ceq 'SETTLE_MEASUREMENT'){throw 'RESOURCE_INTER_CYCLE_MEMORY_MEASUREMENT_UNAVAILABLE'};if($script:Mode -ceq 'SETTLE_UNKNOWN'){throw 'synthetic untrusted settle failure'}}
  function Get-ThriveLensWslPaths {param($Contract)Add-CoreLog 'PATHS';return [pscustomobject]@{PgCtl='/synthetic/pg_ctl';DataRoot='/synthetic/data';Port=55432}}
  function Invoke-ThriveLensGuardedDistro {param($IdentityToken,$LifecycleLock,$TimeoutSeconds,$Contract,[string[]]$Arguments)Test-CoreAuthority -IdentityToken $IdentityToken -LifecycleLock $LifecycleLock -Contract $Contract;Add-CoreLog 'PG_CTL';return [pscustomobject]@{ExitCode=if($script:Mode -ceq 'START_FAIL'){1}else{0};Output=''}}
  function Assert-ThriveLensWslLoopback {param($Paths,$Contract,$IdentityToken,$LifecycleLock)Add-CoreLog 'WSL_LOOPBACK'}
  function Assert-ThriveLensHostLoopback {param($Paths,$Contract)Add-CoreLog 'HOST_LOOPBACK'}
  . ([scriptblock]::Create($CoreDefinition))
  function Invoke-CoreCase([string]$Case){
   $script:Mode=$Case;$script:Log.Clear();$script:LeaseAssertCalls=0;$script:ResourceCalls=0;$script:MemoryCalls=0
   $lock=[Threading.Mutex]::new($false);$lease=[pscustomobject]@{Name='lease'};$token=[pscustomobject]@{Name='token'};$script:ExpectedLock=$lock;$script:ExpectedLease=$lease;$script:ExpectedToken=$token;$script:ExpectedContract=$null;$touched=$false;$attempted=$false;$startCommit=$true;$code=$null
   try{Invoke-ThriveLensPostgresStartUnderLock -ConfigurationLease $lease -IdentityToken $token -LifecycleLock $lock -WslTouched ([ref]$touched) -StartAttempted ([ref]$attempted) -StartCommitResourceGateVerified ([ref]$startCommit)}catch{$code=[string]$_.Exception.Message}finally{$lock.Dispose()}
   return [pscustomobject]@{Code=$code;WslTouched=$touched;StartAttempted=$attempted;StartCommitResourceGateVerified=$startCommit;Log=@($script:Log)}
  }
 }
 try{return & $module {param($Case)Invoke-CoreCase -Case $Case} $Mode}finally{Remove-Module $module -Force -ErrorAction SilentlyContinue}
}
function Invoke-ThriveLensInterCyclePolicyHarness([string]$Definition,$RuntimeValue,$InstallValue){
 $module=New-Module -ArgumentList $Definition -ScriptBlock {
  param([string]$PolicyDefinition)
  . ([scriptblock]::Create($PolicyDefinition))
 }
 try{
  return & $module {
   param($RuntimeValue,$InstallValue)
   $policy=[pscustomobject]@{}
   $policy|Add-Member NoteProperty runtime_minimum_free_memory_bytes $RuntimeValue
   $policy|Add-Member NoteProperty install_minimum_free_memory_bytes $InstallValue
   $code=$null;$value=$null
   try{$value=Get-ThriveLensInterCycleMemoryTargetBytes -Manifest ([pscustomobject]@{resource_policy=$policy})}catch{$code=[string]$_.Exception.Message}
   [pscustomobject]@{Value=$value;Code=$code}
  } $RuntimeValue $InstallValue
 }finally{Remove-Module $module -Force -ErrorAction SilentlyContinue}
}
function Invoke-ThriveLensPreflightAdmissionHarness([string]$Definition,[string]$Mode,[int64]$Threshold=1024){
 $module=New-Module -ArgumentList $Definition -ScriptBlock {
  param([string]$AdmissionDefinition)
  $script:Mode='SUCCESS';$script:Log=[Collections.Generic.List[string]]::new();$script:ExpectedToken=$null;$script:ExpectedLock=$null
  function Add-PreflightLog([string]$Name){$null=$script:Log.Add($Name)}
  function Test-PreflightAuthority($IdentityToken,$LifecycleLock){if(-not [object]::ReferenceEquals($IdentityToken,$script:ExpectedToken) -or -not [object]::ReferenceEquals($LifecycleLock,$script:ExpectedLock)){throw 'SYNTHETIC_AUTHORITY_CHANGED'}}
  function Stop-ThriveLensPreflightDistro {param($IdentityToken,$LifecycleLock)Test-PreflightAuthority $IdentityToken $LifecycleLock;Add-PreflightLog 'TERMINATE'}
  function Wait-ThriveLensInterCycleMemorySettle {param($MinimumFreeMemoryBytes)Add-PreflightLog ("SETTLE:$MinimumFreeMemoryBytes");if($script:Mode -ceq 'SETTLE_LOW'){throw 'RESOURCE_INTER_CYCLE_MEMORY_NOT_SETTLED'};if($script:Mode -ceq 'SETTLE_MEASUREMENT'){throw 'RESOURCE_INTER_CYCLE_MEMORY_MEASUREMENT_UNAVAILABLE'}}
  function Assert-ThriveLensDistroStopped {Add-PreflightLog 'DISTRO_STOPPED';if($script:Mode -ceq 'RELAUNCHED'){throw 'WSL_DISTRO_STILL_RUNNING'}}
  function Assert-ThriveLensWslCleanupIdentity {param($IdentityToken,$LifecycleLock)Test-PreflightAuthority $IdentityToken $LifecycleLock;Add-PreflightLog 'IDENTITY'}
  function Assert-ThriveLensHostPortAbsent {Add-PreflightLog 'HOST_ABSENT'}
  function Get-ThriveLensFreeMemoryBytes {Add-PreflightLog 'RAM';if($script:Mode -ceq 'RAM_LOW'){return [int64]1023};if($script:Mode -ceq 'RAM_INVALID'){return 'invalid'};return [int64]2048}
  . ([scriptblock]::Create($AdmissionDefinition))
  function Invoke-AdmissionCase([string]$Case,[int64]$Minimum){
   $script:Mode=$Case;$script:Log.Clear();$script:ExpectedToken=[pscustomobject]@{Name='token'};$script:ExpectedLock=[Threading.Mutex]::new($false);$code=$null
   try{Complete-ThriveLensPreflightProbeAndAdmit -IdentityToken $script:ExpectedToken -LifecycleLock $script:ExpectedLock -MinimumFreeMemoryBytes $Minimum}catch{$code=[string]$_.Exception.Message}finally{$script:ExpectedLock.Dispose()}
   [pscustomobject]@{Code=$code;Log=@($script:Log)}
  }
 }
 try{return & $module {param($Case,$Minimum)Invoke-AdmissionCase -Case $Case -Minimum $Minimum} $Mode $Threshold}finally{Remove-Module $module -Force -ErrorAction SilentlyContinue}
}
function Invoke-ThriveLensStartAdapterHarness([string]$Source,[string]$Mode){
 $executable=[regex]::Replace($Source,'(?m)^\s*Import-Module[^\r\n]*\r?\n','')
 $tail='(?ms)\$response\s*\|\s*ConvertTo-Json\s+-Compress\s*\r?\n\s*exit\s+\$responseExitCode\s*$'
 if(-not [regex]::IsMatch($executable,$tail)){throw 'START_ADAPTER_HARNESS_TAIL_NOT_FOUND'}
 $executable=[regex]::Replace($executable,$tail,'[pscustomobject]@{ Response = $response; ExitCode = $responseExitCode }')
 $module=New-Module -ArgumentList $executable -ScriptBlock {
  param([string]$AdapterSource)
  $script:Mode='SUCCESS';$script:Log=[Collections.Generic.List[string]]::new();$script:TokenCalls=0;$script:SameToken=$true;$script:SameConfiguration=$true;$script:HarnessLock=$null;$script:HarnessToken=$null;$script:HarnessLease=$null;$script:HarnessContract=$null;$script:HarnessPaths=$null
  function Add-AdapterLog([string]$Name){$null=$script:Log.Add($Name)}
  function Test-AdapterAuthority($IdentityToken,$LifecycleLock){if(-not [object]::ReferenceEquals($IdentityToken,$script:HarnessToken) -or -not [object]::ReferenceEquals($LifecycleLock,$script:HarnessLock)){$script:SameToken=$false;throw 'SYNTHETIC_AUTHORITY_CHANGED'}}
  function Test-AdapterConfiguration($Contract,$Paths=$null){if(-not [object]::ReferenceEquals($Contract,$script:HarnessContract) -or ($null -ne $Paths -and -not [object]::ReferenceEquals($Paths,$script:HarnessPaths))){$script:SameConfiguration=$false;throw 'SYNTHETIC_CONFIGURATION_CHANGED'}}
  function Enter-ThriveLensLifecycleLock {Add-AdapterLog 'LOCK_ENTER';$script:HarnessLock=[Threading.Mutex]::new($false);return $script:HarnessLock}
  function Enter-ThriveLensConfigurationLease {Add-AdapterLog 'LEASE_ENTER';if($script:Mode -ceq 'PRE_LEASE_FAIL'){throw 'CONFIGURATION_LEASE_OPEN_FAILED'};$script:HarnessLease=[pscustomobject]@{Name='lease'};return $script:HarnessLease}
  function Assert-ThriveLensConfigurationLease {param($Lease)Add-AdapterLog 'LEASE_ASSERT';if(-not [object]::ReferenceEquals($Lease,$script:HarnessLease)){throw 'CONFIGURATION_LEASE_INVALID'}}
  function Get-ThriveLensWslContract {param($ConfigurationLease)Add-AdapterLog 'CONTRACT';if(-not [object]::ReferenceEquals($ConfigurationLease,$script:HarnessLease)){throw 'CONFIGURATION_LEASE_INVALID'};$script:HarnessContract=[pscustomobject]@{Name='contract';Manifest=[pscustomobject]@{Name='manifest'}};return $script:HarnessContract}
  function Get-ThriveLensWslPaths {param($Contract)Add-AdapterLog 'PATHS';Test-AdapterConfiguration $Contract;$script:HarnessPaths=[pscustomobject]@{Name='paths';Port=55439};return $script:HarnessPaths}
  function Get-ThriveLensWslCleanupIdentityToken {param($LifecycleLock,$Contract)Add-AdapterLog 'TOKEN';$script:TokenCalls++;if(-not [object]::ReferenceEquals($LifecycleLock,$script:HarnessLock)){throw 'SYNTHETIC_LOCK_CHANGED'};Test-AdapterConfiguration $Contract;$script:HarnessToken=[pscustomobject]@{Name='token'};return $script:HarnessToken}
  function Invoke-ThriveLensPostgresStartUnderLock {
   param($ConfigurationLease,$IdentityToken,$LifecycleLock,[ref]$WslTouched,[ref]$StartAttempted,[ref]$StartCommitResourceGateVerified)
   Add-AdapterLog 'CORE';$StartCommitResourceGateVerified.Value=$false
   Test-AdapterAuthority $IdentityToken $LifecycleLock
   if(-not [object]::ReferenceEquals($ConfigurationLease,$script:HarnessLease)){throw 'CONFIGURATION_LEASE_INVALID'}
   if($script:Mode -cin @('RESOURCE_GATE_UNAVAILABLE','RESOURCE_GATE_FAILED','RESOURCE_GATE_RESULT_INVALID','RESOURCE_GATE_MANIFEST_INVALID','RESOURCE_GATE_PROCESS_START_FAILED','RESOURCE_GATE_TIMEOUT','RESOURCE_GATE_OUTPUT_LIMIT','WSL_STANDARD_INPUT_INVALID','WSL_STANDARD_INPUT_LIMIT_EXCEEDED','INITIAL_OUTPUT_DRAIN')){if($script:Mode -ceq 'INITIAL_OUTPUT_DRAIN'){throw 'RESOURCE_GATE_OUTPUT_DRAIN_INCOMPLETE'};throw $script:Mode}
   switch($script:Mode){
    'EARLY_FAIL'{throw 'RESOURCE_GATE_FAILED'}
    'MID_FAIL'{$WslTouched.Value=$true;throw 'WSL_PACKAGE_MISMATCH'}
    'POST_PROBE_LOW'{$WslTouched.Value=$true;throw 'LOW_FREE_MEMORY_AFTER_WSL_PROBES'}
    'POST_PROBE_MEASUREMENT'{$WslTouched.Value=$true;throw 'MEMORY_MEASUREMENT_UNAVAILABLE_AFTER_WSL_PROBES'}
    'OUTPUT_DRAIN'{$WslTouched.Value=$true;$StartAttempted.Value=$true;throw 'RESOURCE_GATE_OUTPUT_DRAIN_INCOMPLETE'}
    'POST_FAIL'{$WslTouched.Value=$true;$StartAttempted.Value=$true;throw 'POST_MUTATION_RESOURCE_GATE_FAILED'}
    'FINAL_GATE_FAIL'{$WslTouched.Value=$true;$StartAttempted.Value=$true;throw 'POST_MUTATION_RESOURCE_GATE_FAILED'}
    'STOP_FAIL'{$WslTouched.Value=$true;$StartAttempted.Value=$true;throw 'POST_MUTATION_RESOURCE_GATE_FAILED'}
    default{$WslTouched.Value=$true;$StartAttempted.Value=$true;$StartCommitResourceGateVerified.Value=$true}
   }
  }
  function Invoke-ThriveLensResourceGate {param($Manifest)Add-AdapterLog 'FINAL_GATE';if($script:Mode -ceq 'FINAL_GATE_FAIL'){throw 'RESOURCE_GATE_FAILED'}}
  function Test-ThriveLensCredentialCleanupAllowedAfterFailure {param($FailureCode)Add-AdapterLog 'GUEST_POLICY';return $FailureCode -cne 'RESOURCE_GATE_OUTPUT_DRAIN_INCOMPLETE' -and $script:Mode -cnotin @('LEASE_RELEASE_FAIL','LOCK_RELEASE_FAIL')}
  function Assert-ThriveLensWslCleanupIdentity {param($IdentityToken,$LifecycleLock,$Contract)Add-AdapterLog 'IDENTITY';Test-AdapterAuthority $IdentityToken $LifecycleLock;Test-AdapterConfiguration $Contract}
  function Stop-ThriveLensPostgresUnderLock {param($IdentityToken,$LifecycleLock,$Contract,$Paths)Add-AdapterLog 'STOP';Test-AdapterAuthority $IdentityToken $LifecycleLock;Test-AdapterConfiguration $Contract $Paths;if($script:Mode -ceq 'STOP_FAIL'){throw 'POSTGRES_STOP_FAILED'};return $true}
  function Stop-ThriveLensDistroAndVerify {param($IdentityToken,$LifecycleLock,$Contract)Add-AdapterLog 'FORCE';Test-AdapterAuthority $IdentityToken $LifecycleLock;Test-AdapterConfiguration $Contract}
  function Resolve-ThriveLensDistroCleanupFailure {param($FailureCode)return [pscustomobject]@{IdentityAuthorityPreserved=$true}}
  function Assert-ThriveLensDistroStopped {param($Contract)Add-AdapterLog 'DISTRO_ABSENT';Test-AdapterConfiguration $Contract}
  function Assert-ThriveLensHostPortAbsent {param($Paths,$Contract)Add-AdapterLog 'HOST_ABSENT';Test-AdapterConfiguration $Contract $Paths}
  function Exit-ThriveLensLifecycleLock {param($Mutex)Add-AdapterLog 'LOCK_RELEASE';if($script:Mode -ceq 'LOCK_RELEASE_FAIL'){throw 'SYNTHETIC_RELEASE_FAILURE'};Add-AdapterLog 'LOCK_RELEASED'}
  function Exit-ThriveLensConfigurationLease {param($Lease)Add-AdapterLog 'LEASE_RELEASE';if($script:Mode -ceq 'LEASE_RELEASE_FAIL'){throw 'SYNTHETIC_LEASE_RELEASE_FAILURE'};Add-AdapterLog 'LEASE_RELEASED'}
  function Invoke-AdapterCase([string]$Case){
   $script:Mode=$Case;$script:Log.Clear();$script:TokenCalls=0;$script:SameToken=$true;$script:SameConfiguration=$true;$script:HarnessLock=$null;$script:HarnessToken=$null;$script:HarnessLease=$null;$script:HarnessContract=$null;$script:HarnessPaths=$null
   $values=@(& ([scriptblock]::Create($AdapterSource)))
   $adapter=if($values.Count -eq 1){$values[0]}else{$null}
   return [pscustomobject]@{Adapter=$adapter;Log=@($script:Log);TokenCalls=$script:TokenCalls;SameToken=$script:SameToken;SameConfiguration=$script:SameConfiguration;Lock=$script:HarnessLock}
  }
 }
 try{return & $module {param($Case)Invoke-AdapterCase -Case $Case} $Mode}finally{try{& $module {if($null -ne $script:HarnessLock){$script:HarnessLock.Dispose()}}}catch{};Remove-Module $module -Force -ErrorAction SilentlyContinue}
}
function Invoke-ThriveLensStartImportFailureHarness([string]$Source){
 $runtimeImport="Import-Module (Join-Path `$PSScriptRoot 'Runtime.psm1') -Force"
 $executable=Replace-ThriveLensTestSourceOnce -Source $Source -Old $runtimeImport -New "throw 'synthetic private import failure'"
 $wslImport="Import-Module (Join-Path `$PSScriptRoot 'WslRuntime.psm1') -Force"
 $executable=Replace-ThriveLensTestSourceOnce -Source $executable -Old $wslImport -New ''
 $tail='(?ms)\$response\s*\|\s*ConvertTo-Json\s+-Compress\s*\r?\n\s*exit\s+\$responseExitCode\s*$'
 if(-not [regex]::IsMatch($executable,$tail)){throw 'START_IMPORT_FAILURE_HARNESS_TAIL_NOT_FOUND'}
 $executable=[regex]::Replace($executable,$tail,'[pscustomobject]@{ Response = $response; ExitCode = $responseExitCode }')
 $values=@(& ([scriptblock]::Create($executable)))
 if($values.Count -ne 1){return $null}
 return $values[0]
}
function Invoke-ThriveLensRuntimeImportFailureHarness([string]$Source){
 $runtimeImport="Import-Module (Join-Path `$PSScriptRoot 'Runtime.psm1') -Force"
 $executable=Replace-ThriveLensTestSourceOnce -Source $Source -Old $runtimeImport -New "throw 'synthetic private import failure'"
 $executable=Replace-ThriveLensTestSourceOnce -Source $executable -Old '        exit 3' -New '        return'
 $values=@(& ([scriptblock]::Create($executable)))
 if($values.Count -ne 1 -or $values[0] -isnot [string]){return $null}
 try{return $values[0]|ConvertFrom-Json}catch{return $null}
}
function Invoke-ThriveLensRuntimeInitialDrainHarness([string]$Source){
 $parsed=Get-ThriveLensParsedSource -Source $Source
 if($parsed.Errors.Count -ne 0){throw 'RUNTIME_DRAIN_HARNESS_PARSE_FAILED'}
 $outerTry=@($parsed.Ast.EndBlock.Statements|Where-Object{$_ -is [Management.Automation.Language.TryStatementAst]})[0]
 if($null -eq $outerTry){throw 'RUNTIME_DRAIN_HARNESS_TRY_NOT_FOUND'}
 $executable=Replace-ThriveLensTestAstExtent -Source $Source -Extent $outerTry.Body.Extent -New '{ $modulesReady=$true; throw ''RESOURCE_GATE_OUTPUT_DRAIN_INCOMPLETE'' }'
 $executable=Replace-ThriveLensTestSourceOnce -Source $executable -Old '    exit $finalExitCode' -New '    return'
 $module=New-Module -ArgumentList $executable -ScriptBlock {
  param([string]$RuntimeSource)
  function Resolve-ThriveLensRuntimePublicCode {param($Code)return $Code}
  function Resolve-ThriveLensRuntimeCleanupOutcome {
   param($OriginalCode,$OriginalExitCode,$CleanupRequired,$CleanupAuthorityVerified,$CredentialCleanupRequired,$CredentialRemoveFailed,$CredentialRootFailureCode,$CredentialAbsenceVerified,$IdentityChanged,$PostgresStopFailed,$DistroTerminateFailed,$DistroAbsenceCheckFailed,$HostAbsenceCheckFailed,$DistroAbsent,$HostAbsent,$LockReleaseFailed)
   return [pscustomobject]@{Status='BLOCKED';Code=$OriginalCode;ExitCode=$OriginalExitCode;OriginalCode=$OriginalCode;FailureStages=@('RESOURCE_GATE');CleanupVerified=$true}
  }
  function Invoke-RuntimeDrainCase {
   $values=@(& ([scriptblock]::Create($RuntimeSource)))
   if($values.Count -ne 1 -or $values[0] -isnot [string]){return $null}
   try{return $values[0]|ConvertFrom-Json}catch{return $null}
  }
 }
 try{return & $module {Invoke-RuntimeDrainCase}}finally{Remove-Module $module -Force -ErrorAction SilentlyContinue}
}
function Invoke-ThriveLensClusterIdentityHarness([string]$Definition,[string]$Mode){
 $module=New-Module -ArgumentList $Definition -ScriptBlock {
  param([string]$IdentityDefinition)
  $script:Mode='SUCCESS';$script:Log=[Collections.Generic.List[string]]::new();$script:ExpectedToken=$null;$script:ExpectedLock=$null;$script:ExpectedContract=$null;$script:ExpectedPaths=$null;$script:Bound=$true
  function Assert-ThriveLensWslCleanupIdentity {param($IdentityToken,$LifecycleLock,$Contract)$script:Log.Add('IDENTITY');if(-not [object]::ReferenceEquals($IdentityToken,$script:ExpectedToken)-or-not[object]::ReferenceEquals($LifecycleLock,$script:ExpectedLock)-or-not[object]::ReferenceEquals($Contract,$script:ExpectedContract)){$script:Bound=$false;throw 'AUTHORITY_CHANGED'}}
  function Invoke-ThriveLensGuardedDistro {param($IdentityToken,$LifecycleLock,$Contract,[switch]$CapturePrivateStandardError,[string[]]$Arguments)$script:Log.Add('PG_CONTROLDATA');if(-not [object]::ReferenceEquals($IdentityToken,$script:ExpectedToken)-or-not[object]::ReferenceEquals($LifecycleLock,$script:ExpectedLock)-or-not[object]::ReferenceEquals($Contract,$script:ExpectedContract)-or-not$CapturePrivateStandardError-or($Arguments-join ',')-cne'/usr/bin/env,-i,LC_ALL=C,LANG=C,/synthetic/pg_controldata,/synthetic/data'){$script:Bound=$false;throw 'ARGUMENTS_CHANGED'};$output=switch($script:Mode){'DUPLICATE'{"Database system identifier: 7234567890123456789`nDatabase system identifier: 7234567890123456789`n"};'ZERO'{"Database system identifier: 0`n"};'OVERFLOW'{"Database system identifier: 18446744073709551616`n"};'MALFORMED'{"Database system identifier: +7234567890123456789`n"};default{"pg_control version number: 1700`nDatabase system identifier: 7234567890123456789`n"}};return [pscustomobject]@{ExitCode=if($script:Mode-ceq'EXIT'){1}else{0};PrivateStandardOutput=$output;PrivateStandardError=if($script:Mode-ceq'STDERR'){'private failure'}else{''};Output=$output}}
  . ([scriptblock]::Create($IdentityDefinition))
  function Invoke-IdentityCase([string]$Case){$script:Mode=$Case;$script:Log.Clear();$script:Bound=$true;$script:ExpectedToken=[pscustomobject]@{Name='token'};$script:ExpectedLock=[Threading.Mutex]::new($false);$script:ExpectedContract=[pscustomobject]@{Name='contract'};$script:ExpectedPaths=[pscustomobject]@{PgControlData='/synthetic/pg_controldata';DataRoot='/synthetic/data'};$value=$null;$code=$null;try{$value=Get-ThriveLensPrivateClusterIdentityFingerprint -IdentityToken $script:ExpectedToken -LifecycleLock $script:ExpectedLock -Contract $script:ExpectedContract -Paths $script:ExpectedPaths}catch{$code=[string]$_.Exception.Message}finally{$script:ExpectedLock.Dispose()};return [pscustomobject]@{Value=$value;Code=$code;Bound=$script:Bound;Log=@($script:Log)}}
 }
 try{return & $module {param($Case)Invoke-IdentityCase -Case $Case} $Mode}finally{Remove-Module $module -Force -ErrorAction SilentlyContinue}
}
function Replace-ThriveLensTestSourceOnce([string]$Source,[string]$Old,[string]$New){
 $first=$Source.IndexOf($Old,[StringComparison]::Ordinal)
 if($first -lt 0 -or $Source.IndexOf($Old,$first+$Old.Length,[StringComparison]::Ordinal) -ge 0){throw 'TEST_MUTATION_TARGET_NOT_UNIQUE'}
 return $Source.Substring(0,$first)+$New+$Source.Substring($first+$Old.Length)
}
function Replace-ThriveLensTestSourceOccurrence([string]$Source,[string]$Old,[string]$New,[int]$Occurrence=1){
 if($Occurrence -lt 1){throw 'TEST_MUTATION_OCCURRENCE_INVALID'}
 $offset=-1
 for($index=0;$index -lt $Occurrence;$index++){
  $offset=$Source.IndexOf($Old,$offset+1,[StringComparison]::Ordinal)
  if($offset -lt 0){throw 'TEST_MUTATION_TARGET_NOT_FOUND'}
 }
 return $Source.Substring(0,$offset)+$New+$Source.Substring($offset+$Old.Length)
}
function Replace-ThriveLensTestAstExtent([string]$Source,[Management.Automation.Language.IScriptExtent]$Extent,[string]$New){
 return $Source.Substring(0,$Extent.StartOffset)+$New+$Source.Substring($Extent.EndOffset)
}
try{
 $root=(Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
 $manifest=Get-Content (Join-Path $root 'config\toolchains\backend.json') -Raw|ConvertFrom-Json
 A ([string]$manifest.wsl_fallback.distribution_name -ceq 'ThriveLens-R0') 'DISTRO_NAME'
 A ([string]$manifest.wsl_fallback.distribution_install_root -ceq '%LOCALAPPDATA%\ThriveLens\wsl\ThriveLens-R0') 'DISTRO_ROOT'
 A ([int64]$manifest.wsl_fallback.maximum_vhd_bytes -eq 6442450944) 'VHD_LIMIT'
 A ([string]$manifest.wsl_fallback.pgdg.signing_key_fingerprint -ceq 'B97B0AFCAA1A47F044F244A07FCC7D46ACCC4CF8') 'KEY_FINGERPRINT'
 A (@($manifest.wsl_fallback.pgdg.package_closure).Count -eq 9) 'PACKAGE_CLOSURE'
 A ((@($manifest.wsl_fallback.pgdg.held_packages)-join ',') -ceq 'libjson-perl,libllvm19,libpq5,libxslt1.1,postgresql-17,postgresql-client-17,postgresql-client-common,postgresql-common,ssl-cert') 'HOLDS'
 A ([string]$manifest.wsl_fallback.cluster_data_root -ceq '/var/lib/thrivelens/postgresql/r0') 'POSIX_DATA'
 A ([string]$manifest.wsl_fallback.cluster_log_root -ceq '/var/log/thrivelens/postgresql/r0') 'POSIX_LOG'
 A (-not [bool]$manifest.wsl_fallback.logs_persisted) 'NO_RAW_LOG'
 $module=Get-Content (Join-Path $PSScriptRoot 'WslRuntime.psm1') -Raw
 $wslModuleParsed=Get-ThriveLensParsedSource -Source $module
 $wslFunctions=@($wslModuleParsed.Ast.FindAll({param($node)$node -is [Management.Automation.Language.FunctionDefinitionAst]},$true))
 $invokeWslAst=@($wslFunctions|Where-Object{$_.Name -ceq 'Invoke-ThriveLensWsl'})
 $invokeWslBody=if($invokeWslAst.Count -eq 1){$invokeWslAst[0].Extent.Text}else{''}
 Import-Module (Join-Path $PSScriptRoot 'Runtime.psm1') -Force
 Import-Module (Join-Path $PSScriptRoot 'WslRuntime.psm1') -Force
 $invalidWslSecurityVersions=@(@('OutputBudget','BoundedCaptureStream','HostFileIdentity','MutexOwnershipVerifier')|Where-Object{$type=("ThriveLens.WslSecurityV2.$_" -as [type]);$null -eq $type -or $null -eq $type.GetField('ContractVersion',[Reflection.BindingFlags]'Public,Static') -or $type.GetField('ContractVersion',[Reflection.BindingFlags]'Public,Static').GetRawConstantValue() -ne 2})
 A ((Test-ThriveLensWslSecurityTypeContract -Source $module) -and $invalidWslSecurityVersions.Count -eq 0) 'WSL_SECURITY_V2_EXACT_IMPORT_AND_BEHAVIOR_ATTESTATION'
 A ($invokeWslBody -match '\[ThriveLens\.WslSecurityV2\.OutputBudget\]::new\(131072\)' -and $invokeWslBody -match '\[ThriveLens\.WslSecurityV2\.BoundedCaptureStream\]::new\(\$budget\)') 'BOUNDED_CAPTURE'
 A ($module -match 'Kill\(\$true\)') 'TREE_KILL'
 A ($module -match "distribution_name -cne 'ThriveLens-R0'") 'EXACT_TARGET'
 A ($module -match 'WSL_CLUSTER_PATH_SYMLINK_REJECTED') 'SYMLINK_GATE'
 A ($module -match 'POSTGRES_PROCESS_STILL_PRESENT') 'PROCESS_ABSENCE'
 A ($module -match 'Local\\ThriveLens-R0-PostgreSQL-Lifecycle') 'LIFECYCLE_LOCK'
 A ($invokeWslBody -notmatch "--terminate|WSL_PROCESS_TREE_TERMINATION_UNPROVEN") 'GENERIC_WSL_NEVER_TERMINATES_DISTRO'
 A ($invokeWslBody -match '\$timeoutMilliseconds\s*=\s*\[Math\]::BigMul\(\[int\]\$TimeoutSeconds,1000\)' -and
    $invokeWslBody -match '\$stopwatch\s*=\s*\[Diagnostics\.Stopwatch\]::StartNew\(\)' -and
    $invokeWslBody -match '\$stopwatch\.ElapsedMilliseconds\s*-lt\s*\$timeoutMilliseconds' -and
    $invokeWslBody -notmatch 'DateTime|UtcNow') 'WSL_RUNNER_ONE_MONOTONIC_DEADLINE'
 A ($invokeWslBody -match 'UTF8Encoding\]::new\(\$false,\$true\)\.GetBytes\(\$StandardInput\)' -and
    $invokeWslBody -match '\$stdinBytes\.Length\s*-gt\s*512' -and
    $invokeWslBody -match "throw 'WSL_STANDARD_INPUT_INVALID'" -and $invokeWslBody -match "throw 'WSL_STANDARD_INPUT_LIMIT_EXCEEDED'" -and
    $invokeWslBody -match '\[Array\]::Clear\(\$stdinBytes,0,\$stdinBytes\.Length\)') 'WSL_RUNNER_STDIN_STRICT_PRESTART_BOUNDARY'
 A ($invokeWslBody -match '\$stdinWriteTask=\$process\.StandardInput\.BaseStream\.WriteAsync' -and
    $invokeWslBody -match '\$stdinFlushTask=\$process\.StandardInput\.BaseStream\.FlushAsync\(\)' -and
    $invokeWslBody -match 'foreach\(\$ioTask\s+in\s+@\(\$stdoutTask,\$stderrTask,\$stdinWriteTask,\$stdinFlushTask\)\)' -and
    $invokeWslBody -match 'if\(-not \$process\.HasExited\)\{\$process\.Kill\(\$true\)\}' -and
    $invokeWslBody -match '\$rootReaped=\$process\.WaitForExit\(5000\)' -and
    $invokeWslBody -match 'if\(-not \$cleanupProven\)\{throw ''WSL_OUTPUT_DRAIN_INCOMPLETE''\}') 'WSL_RUNNER_KILL_REAP_JOIN_UNCERTAINTY'
 A ($invokeWslBody -match 'if\(\$stdoutComplete\)\{\$stdoutSink\.Dispose\(\)\}' -and
    $invokeWslBody -match 'if\(\$stderrComplete\)\{\$stderrSink\.Dispose\(\)\}' -and
    $invokeWslBody -match 'if\(\$rootInactive\s*-and\s*\$stdoutComplete\s*-and\s*\$stderrComplete\s*-and\s*\$stdinWriteComplete\s*-and\s*\$stdinFlushComplete\)\{\$process\.Dispose\(\)\}') 'WSL_RUNNER_NO_ACTIVE_TASK_SINK_OR_PROCESS_DISPOSE'
 $terminateStart=$module.IndexOf('function Stop-ThriveLensDistroAndVerify');$terminateEnd=$module.IndexOf('function Assert-ThriveLensDistroStopped',$terminateStart);$terminateBody=if($terminateStart -ge 0 -and $terminateEnd -gt $terminateStart){$module.Substring($terminateStart,$terminateEnd-$terminateStart)}else{''}
 A ($terminateBody -match 'IdentityToken' -and $terminateBody -match 'LifecycleLock' -and $terminateBody -match 'Assert-ThriveLensWslCleanupIdentity' -and $terminateBody -match 'finally') 'TERMINATE_REVALIDATES_IDENTITY_PRE_POST'
 $runtimeModule=Get-Content (Join-Path $PSScriptRoot 'Runtime.psm1') -Raw
 $readerStart=$runtimeModule.IndexOf('function Read-ThriveLensPostgresBootstrapSecret');$readerEnd=if($readerStart -ge 0){$runtimeModule.IndexOf('function Assert-ThriveLensVersionText',$readerStart)}else{-1};$readerBody=if($readerStart -ge 0 -and $readerEnd -gt $readerStart){$runtimeModule.Substring($readerStart,$readerEnd-$readerStart)}else{''}
 A ($readerBody -match 'Assert-ThriveLensSecretRootAcl') 'SECRET_READER_PARENT_ACL'
 A ($readerBody -match 'Assert-ThriveLensSecretFileAclRules') 'SECRET_READER_FILE_ACL'
 A ($readerBody -match '\[IO\.FileShare\]::None') 'SECRET_READER_EXCLUSIVE_OPEN'
 Import-Module (Join-Path $PSScriptRoot 'Runtime.psm1') -Force
 Import-Module (Join-Path $PSScriptRoot 'WslRuntime.psm1') -Force
 A (Test-ThriveLensMemoryPolicyContract -Source $runtimeModule) 'MEMORY_POLICY_STRICT_MAX_CONTRACT'
 $memoryPolicyManifest=[pscustomobject]@{resource_policy=[pscustomobject]@{runtime_minimum_free_memory_bytes=[int64]1024;install_minimum_free_memory_bytes=[int64]2048}}
 $memoryPolicyThresholds=Get-ThriveLensMemoryPolicyThresholds -Manifest $memoryPolicyManifest
 A ($memoryPolicyThresholds.RuntimeMinimumBytes -is [int64] -and $memoryPolicyThresholds.RuntimeMinimumBytes -eq 1024 -and
    $memoryPolicyThresholds.InstallMinimumBytes -is [int64] -and $memoryPolicyThresholds.InstallMinimumBytes -eq 2048 -and
    $memoryPolicyThresholds.StartReclaimTargetBytes -is [int64] -and $memoryPolicyThresholds.StartReclaimTargetBytes -eq 2048) 'MEMORY_POLICY_INSTALL_MAX_EXECUTABLE'
 $runtimeMaxManifest=[pscustomobject]@{resource_policy=[pscustomobject]@{runtime_minimum_free_memory_bytes=[int64]4096;install_minimum_free_memory_bytes=[int64]2048}}
 A ((Get-ThriveLensMemoryPolicyThresholds -Manifest $runtimeMaxManifest).StartReclaimTargetBytes -eq 4096) 'MEMORY_POLICY_RUNTIME_MAX_EXECUTABLE'
 foreach($invalidMemoryPolicy in @(
  [pscustomobject]@{runtime_minimum_free_memory_bytes=$true;install_minimum_free_memory_bytes=[int64]2048},
  [pscustomobject]@{runtime_minimum_free_memory_bytes=$null;install_minimum_free_memory_bytes=[int64]2048},
  [pscustomobject]@{runtime_minimum_free_memory_bytes=[int]1024;install_minimum_free_memory_bytes=[int64]2048},
  [pscustomobject]@{runtime_minimum_free_memory_bytes=[double]1024;install_minimum_free_memory_bytes=[int64]2048},
  [pscustomobject]@{runtime_minimum_free_memory_bytes=[int64]0;install_minimum_free_memory_bytes=[int64]2048},
  [pscustomobject]@{runtime_minimum_free_memory_bytes=[int64]1024;install_minimum_free_memory_bytes=[int64]-1}
 )){A (Test-ThrowsExact {Get-ThriveLensMemoryPolicyThresholds -Manifest ([pscustomobject]@{resource_policy=$invalidMemoryPolicy})} 'RUNTIME_MEMORY_POLICY_INVALID') 'MEMORY_POLICY_INVALID_TYPE_OR_VALUE_FAILS_CLOSED'}
 A (('ThriveLens.WslSecurityV2.OutputBudget' -as [type]) -and ('ThriveLens.WslSecurityV2.BoundedCaptureStream' -as [type])) 'WSL_SECURITY_V2_FORCE_REIMPORT_SAME_PROCESS'
 $memoryType=[ThriveLens.HostMemorySnapshot]
 $nonPublicStatic=[Reflection.BindingFlags]::NonPublic -bor [Reflection.BindingFlags]::Static
 $nonPublicNested=[Reflection.BindingFlags]::NonPublic
 $memoryNativeMethod=$memoryType.GetMethod('GlobalMemoryStatusEx',$nonPublicStatic)
 $memoryNativeAttribute=@($memoryNativeMethod.GetCustomAttributes([Runtime.InteropServices.DllImportAttribute],$false))[0]
 $memoryReturnAttribute=@($memoryNativeMethod.ReturnParameter.GetCustomAttributes([Runtime.InteropServices.MarshalAsAttribute],$false))[0]
 $memoryStatusType=$memoryType.GetNestedType('MEMORYSTATUSEX',$nonPublicNested)
 $memoryFields=@($memoryStatusType.GetFields([Reflection.BindingFlags]::Public -bor [Reflection.BindingFlags]::Instance)|Sort-Object MetadataToken)
 A ($runtimeModule -notmatch 'Get-CimInstance\s+Win32_OperatingSystem' -and $runtimeModule -match 'namespace ThriveLens' -and $runtimeModule -match 'public static class HostMemorySnapshot') 'HOST_MEMORY_P_INVOKE_SOURCE_BOUNDARY'
 $memoryStatusInstance=[Activator]::CreateInstance($memoryStatusType,$true)
 A ($runtimeModule -match '\[StructLayout\(LayoutKind\.Sequential, Pack = 8\)\]' -and [Runtime.InteropServices.Marshal]::SizeOf($memoryStatusInstance) -eq 64) 'HOST_MEMORY_MEMORYSTATUSEX_ABI_64'
 A ($memoryNativeAttribute.Value -ceq 'kernel32.dll' -and $memoryNativeAttribute.ExactSpelling -and $memoryNativeAttribute.SetLastError -and $memoryReturnAttribute.Value -eq [Runtime.InteropServices.UnmanagedType]::Bool) 'HOST_MEMORY_PINVOKE_MARSHALLING'
 A (($memoryFields.Name -join ',') -ceq 'dwLength,dwMemoryLoad,ullTotalPhys,ullAvailPhys,ullTotalPageFile,ullAvailPageFile,ullTotalVirtual,ullAvailVirtual,ullAvailExtendedVirtual' -and ($memoryFields.FieldType.Name -join ',') -ceq 'UInt32,UInt32,UInt64,UInt64,UInt64,UInt64,UInt64,UInt64,UInt64') 'HOST_MEMORY_FIELD_LAYOUT_EXACT'
 $maximumSigned=[ThriveLens.HostMemorySnapshot]::ToSignedByteCount([uint64][int64]::MaxValue);$syntheticOverflow=$false;try{$null=[ThriveLens.HostMemorySnapshot]::ToSignedByteCount([uint64]::MaxValue)}catch{$syntheticOverflow=$_.Exception.InnerException -is [OverflowException] -or $_.Exception -is [OverflowException]}
 A ($maximumSigned -is [int64] -and $maximumSigned -eq [int64]::MaxValue -and $syntheticOverflow) 'HOST_MEMORY_CHECKED_SIGNED_CONVERSION'
 $liveFreeMemory=Get-ThriveLensFreeMemoryBytes
 A ($liveFreeMemory -is [int64] -and $liveFreeMemory -gt 0) 'HOST_MEMORY_LIVE_SAMPLE_SHAPE'
 $runtimeModuleTokens=$null;$runtimeModuleParseErrors=$null;$runtimeModuleAst=[Management.Automation.Language.Parser]::ParseInput($runtimeModule,[ref]$runtimeModuleTokens,[ref]$runtimeModuleParseErrors)
 $settleFunctions=@($runtimeModuleAst.FindAll({param($node)$node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq 'Wait-ThriveLensInterCycleMemorySettle'},$true))
 A ($runtimeModuleParseErrors.Count -eq 0 -and $settleFunctions.Count -eq 1) 'INTER_CYCLE_MEMORY_HELPER_AST_PRESENT'
 $settleDefinition=if($settleFunctions.Count -eq 1){$settleFunctions[0].Extent.Text}else{''}
 A ($settleDefinition -match '\$timeoutMilliseconds\s*=\s*90000' -and $settleDefinition -notmatch '\$timeoutMilliseconds\s*=\s*30000' -and $settleDefinition -match '\$sampleIntervalMilliseconds\s*=\s*1000' -and $settleDefinition -match '\$requiredConsecutiveSamples\s*=\s*3') 'INTER_CYCLE_MEMORY_FIXED_POLICY'
 A (Test-ThriveLensSettleHostOnlyContract -Source $runtimeModule) 'INTER_CYCLE_MEMORY_HOST_ONLY'
 $settleCommands=@($settleFunctions[0].FindAll({param($node)$node -is [Management.Automation.Language.CommandAst] -and $null -ne $node.GetCommandName()},$true)|ForEach-Object{$_.GetCommandName()}|Sort-Object -Unique)
 A (($settleCommands -join ',') -ceq 'Get-ThriveLensFreeMemoryBytes,Start-Sleep') 'INTER_CYCLE_MEMORY_COMMAND_ALLOWLIST_EXACT'
 A (-not (Test-ThriveLensAstHasProcessTypeInvocation -Ast $settleFunctions[0] -StartOffset $settleFunctions[0].Extent.StartOffset -EndOffset $settleFunctions[0].Extent.EndOffset)) 'INTER_CYCLE_MEMORY_NO_PROCESS_CREATION'
 $boundedSettleDefinition=$settleDefinition.Replace('$timeoutMilliseconds = 90000','$timeoutMilliseconds = 2000').Replace('$sampleIntervalMilliseconds = 1000','$sampleIntervalMilliseconds = 1')
 $zeroTimeoutSettleDefinition=$settleDefinition.Replace('$timeoutMilliseconds = 90000','$timeoutMilliseconds = 0').Replace('$sampleIntervalMilliseconds = 1000','$sampleIntervalMilliseconds = 1')
 A ($boundedSettleDefinition -cne $settleDefinition -and $boundedSettleDefinition -match '\$timeoutMilliseconds\s*=\s*2000(?:\D|$)' -and $boundedSettleDefinition -match '\$sampleIntervalMilliseconds\s*=\s*1(?:\D|$)' -and $zeroTimeoutSettleDefinition -match '\$timeoutMilliseconds\s*=\s*0(?:\D|$)') 'INTER_CYCLE_MEMORY_TEST_DEADLINE_BOUNDED'
 $settleTestModuleScript={
  param([string]$Definition)
  $script:Samples=@();$script:SampleIndex=0;$script:MeasurementMode='VALUES';$script:SleepCalls=0
  function Get-ThriveLensFreeMemoryBytes {
   if($script:MeasurementMode -ceq 'THROW'){throw 'SYNTHETIC_MEASUREMENT_FAILURE'}
   if($script:MeasurementMode -ceq 'INVALID'){return 'not-an-integer'}
   if($script:Samples.Count -eq 0){return $null}
   $position=[Math]::Min($script:SampleIndex,$script:Samples.Count-1);$script:SampleIndex++;return $script:Samples[$position]
  }
  function Start-Sleep {param([Parameter(Mandatory)][int]$Milliseconds)if($Milliseconds -lt 1 -or $Milliseconds -gt 30){throw 'SYNTHETIC_SLEEP_OUT_OF_BOUNDS'};$script:SleepCalls++}
  . ([scriptblock]::Create($Definition))
 }
 $settleTestModule=New-Module -ArgumentList $boundedSettleDefinition -ScriptBlock $settleTestModuleScript
 $boundedSettleTestModule=$settleTestModule
 $zeroTimeoutSettleTestModule=$null
 try{
  $runSettleCase={param([object[]]$Samples,[int64]$Threshold,[string]$Mode)& $settleTestModule {param($values,$minimum,$measurementMode)$script:Samples=@($values);$script:SampleIndex=0;$script:MeasurementMode=$measurementMode;$script:SleepCalls=0;$code=$null;try{Wait-ThriveLensInterCycleMemorySettle -MinimumFreeMemoryBytes $minimum}catch{$code=$_.Exception.Message};[pscustomobject]@{Code=$code;Samples=$script:SampleIndex;Sleeps=$script:SleepCalls}} $Samples $Threshold $Mode}
  $memoryThreshold=[int64]4096
  $exactCase=& $runSettleCase @($memoryThreshold,$memoryThreshold,$memoryThreshold) $memoryThreshold 'VALUES';A ($null -eq $exactCase.Code -and $exactCase.Samples -eq 3 -and $exactCase.Sleeps -eq 2) 'INTER_CYCLE_MEMORY_EXACT_THRESHOLD_ACCEPTED'
  $belowCase=& $runSettleCase @(4095,$memoryThreshold,$memoryThreshold,$memoryThreshold) $memoryThreshold 'VALUES';A ($null -eq $belowCase.Code -and $belowCase.Samples -eq 4) 'INTER_CYCLE_MEMORY_BELOW_THRESHOLD_NOT_COUNTED'
  $resetCase=& $runSettleCase @($memoryThreshold,$memoryThreshold,4095,$memoryThreshold,$memoryThreshold,$memoryThreshold) $memoryThreshold 'VALUES';A ($null -eq $resetCase.Code -and $resetCase.Samples -eq 6) 'INTER_CYCLE_MEMORY_BELOW_RESETS_CONSECUTIVE_COUNT'
  $measurementCase=& $runSettleCase @($memoryThreshold) $memoryThreshold 'THROW';A ($measurementCase.Code -ceq 'RESOURCE_INTER_CYCLE_MEMORY_MEASUREMENT_UNAVAILABLE' -and $measurementCase.Samples -eq 0) 'INTER_CYCLE_MEMORY_MEASUREMENT_FAILURE_MAPPED'
  $invalidCase=& $runSettleCase @('invalid') $memoryThreshold 'INVALID';A ($invalidCase.Code -ceq 'RESOURCE_INTER_CYCLE_MEMORY_MEASUREMENT_UNAVAILABLE') 'INTER_CYCLE_MEMORY_INVALID_SAMPLE_MAPPED'
  $zeroTimeoutSettleTestModule=New-Module -ArgumentList $zeroTimeoutSettleDefinition -ScriptBlock $settleTestModuleScript
  $settleTestModule=$zeroTimeoutSettleTestModule
  $timeoutWatch=[Diagnostics.Stopwatch]::StartNew();$timeoutCase=& $runSettleCase @(4095) $memoryThreshold 'VALUES';$timeoutWatch.Stop();A ($timeoutCase.Code -ceq 'RESOURCE_INTER_CYCLE_MEMORY_NOT_SETTLED' -and $timeoutCase.Samples -eq 1 -and $timeoutCase.Sleeps -eq 0 -and $timeoutWatch.ElapsedMilliseconds -lt 1000) 'INTER_CYCLE_MEMORY_TIMEOUT_BOUNDED'
 }finally{if($null -ne $zeroTimeoutSettleTestModule){Remove-Module $zeroTimeoutSettleTestModule -Force -ErrorAction SilentlyContinue};if($null -ne $boundedSettleTestModule){Remove-Module $boundedSettleTestModule -Force -ErrorAction SilentlyContinue}}
 $identityToken=[pscustomobject]@{SchemaVersion=1;RegistryId='11111111-1111-1111-1111-111111111111';DistributionName='ThriveLens-R0';Version=2;BasePath='C:\Synthetic\ThriveLens-R0';VhdPath='C:\Synthetic\ThriveLens-R0\ext4.vhdx';VhdIdentity='00000001:0000000000000001'}
 $sameIdentity=[pscustomobject]@{SchemaVersion=1;RegistryId=$identityToken.RegistryId;DistributionName=$identityToken.DistributionName;Version=2;BasePath=$identityToken.BasePath;VhdPath=$identityToken.VhdPath;VhdIdentity=$identityToken.VhdIdentity}
 A (Compare-ThriveLensWslCleanupIdentityToken -Expected $identityToken -Actual $sameIdentity) 'CLEANUP_IDENTITY_EXACT_ACCEPTED'
 $replacementIdentity=[pscustomobject]@{SchemaVersion=1;RegistryId='22222222-2222-2222-2222-222222222222';DistributionName='ThriveLens-R0';Version=2;BasePath=$identityToken.BasePath;VhdPath=$identityToken.VhdPath;VhdIdentity='00000001:0000000000000002'}
 A (Test-ThrowsExact {Compare-ThriveLensWslCleanupIdentityToken -Expected $identityToken -Actual $replacementIdentity} 'WSL_CLEANUP_IDENTITY_CHANGED') 'CLEANUP_SAME_NAME_REPLACEMENT_REJECTED'
 $unownedLock=[Threading.Mutex]::new($false)
 try{A (Test-ThrowsExact {Stop-ThriveLensDistroAndVerify -IdentityToken $identityToken -LifecycleLock $unownedLock} 'LIFECYCLE_LOCK_OWNERSHIP_REQUIRED') 'TERMINATE_WITHOUT_HELD_LOCK_REJECTED'}finally{$unownedLock.Dispose()}
 $nativeLock=Enter-ThriveLensLifecycleLock -TimeoutSeconds 2
 try{
  A ([ThriveLens.WslSecurityV2.MutexOwnershipVerifier]::IsOwnedByCurrentThread($nativeLock)) 'NATIVE_CURRENT_THREAD_MUTEX_OWNERSHIP'
  A (-not [ThriveLens.WslSecurityV2.MutexOwnershipVerifier]::CheckFromNewThread($nativeLock)) 'NATIVE_CROSS_THREAD_MUTEX_REJECTED'
 }finally{Exit-ThriveLensLifecycleLock -Mutex $nativeLock}
 $releasedLock=Enter-ThriveLensLifecycleLock -TimeoutSeconds 2
 try{
  $releasedLock.ReleaseMutex()
  A (Test-ThrowsExact {Stop-ThriveLensDistroAndVerify -IdentityToken $identityToken -LifecycleLock $releasedLock} 'LIFECYCLE_LOCK_OWNERSHIP_REQUIRED') 'NATIVE_RELEASED_MUTEX_REJECTED'
  $null=$releasedLock.WaitOne(0)
 }finally{Exit-ThriveLensLifecycleLock -Mutex $releasedLock}
 $wrongPasswordPath='/run/thrivelens-r0-wrong-0123456789abcdef0123456789abcdef.pgpass'
 $otherWrongPasswordPath='/run/thrivelens-r0-wrong-fedcba9876543210fedcba9876543210.pgpass'
 $authError='psql: error: connection to server at "127.0.0.1", port 55432 failed: FATAL:  password authentication failed for user "tl_bootstrap"'
 $passwordFileError='password retrieved from file "'+$wrongPasswordPath+'"'
 $acceptedAuthDiagnostics=@(
  ($authError+"`n"+$passwordFileError),($authError+"`n"+$passwordFileError+"`n")
 )
 A ($acceptedAuthDiagnostics.Count -eq 2) 'WRONG_PASSWORD_ACCEPTED_MATRIX_COMPLETE'
 foreach($acceptedDiagnostic in $acceptedAuthDiagnostics){
  $authRejected=Resolve-ThriveLensWrongPasswordProbe -ExitCode 2 -PrivateStandardOutput '' -PrivateStandardError $acceptedDiagnostic -ExpectedPasswordFile $wrongPasswordPath -ServerUsableAfterProbe $true
  A ($authRejected.Status -ceq 'AUTHENTICATION_REJECTED' -and $authRejected.ExitCode -eq 2) 'WRONG_PASSWORD_EXACT_REJECTION_ACCEPTED'
 }
 A (Test-ThrowsExact {Resolve-ThriveLensWrongPasswordProbe -ExitCode 0 -PrivateStandardOutput '1' -PrivateStandardError '' -ExpectedPasswordFile $wrongPasswordPath -ServerUsableAfterProbe $true} 'WRONG_PASSWORD_WAS_ACCEPTED') 'WRONG_PASSWORD_SUCCESS_REJECTED'
 A (Test-ThrowsExact {Resolve-ThriveLensWrongPasswordProbe -ExitCode 2 -PrivateStandardOutput ' ' -PrivateStandardError $authError -ExpectedPasswordFile $wrongPasswordPath -ServerUsableAfterProbe $true} 'WRONG_PASSWORD_PROBE_UNEXPECTED_OUTPUT') 'WRONG_PASSWORD_WHITESPACE_STDOUT_REJECTED'
 A (Test-ThrowsExact {Resolve-ThriveLensWrongPasswordProbe -ExitCode 1 -PrivateStandardOutput '' -PrivateStandardError ($authError+"`n"+$passwordFileError) -ExpectedPasswordFile $wrongPasswordPath -ServerUsableAfterProbe $true} 'WRONG_PASSWORD_PROBE_UNRELATED_FAILURE') 'WRONG_PASSWORD_WRONG_EXIT_REJECTED'
 $authNearMisses=@(
  $authError,($authError+"`n"),($authError+"`r`n"),
  ('prefix'+$authError),($authError+' suffix'),($authError+"`n`n"),($authError+"`r`n`r`n"),
  ($authError -replace '127\.0\.0\.1','localhost'),($authError -replace '55432','55433'),
  ($authError -replace 'tl_bootstrap','postgres'),(($authError -replace 'FATAL','fatal')+"`n"+$passwordFileError),'psql: error: client executable failure',
  $passwordFileError,($authError+"`npassword retrieved from file `"$otherWrongPasswordPath`""),
  ($authError+"`n"+$passwordFileError+' suffix'),($authError+"`n"+$passwordFileError+"`nextra"),
  ($authError+"`n"+$passwordFileError+"`n`n"),($authError+"`r"),
  ($authError+"`n"+$passwordFileError+"`r"),($authError+"`r`n"+$passwordFileError+"`r`n"),
  ($authError+"`t")
 )
 A ($authNearMisses.Count -eq 21) 'WRONG_PASSWORD_NEAR_MISS_MATRIX_COMPLETE'
 foreach($nearMiss in $authNearMisses){
  A (Test-ThrowsExact {Resolve-ThriveLensWrongPasswordProbe -ExitCode 2 -PrivateStandardOutput '' -PrivateStandardError $nearMiss -ExpectedPasswordFile $wrongPasswordPath -ServerUsableAfterProbe $true} 'WRONG_PASSWORD_PROBE_UNRELATED_FAILURE') 'WRONG_PASSWORD_DIAGNOSTIC_NEAR_MISS_REJECTED'
 }
 foreach($hostileDiagnostic in @(
  ($authError+[char]0),($authError+[char]0x00e9),[string]::new('x',513)
 )){
  A (Test-ThrowsExact {Resolve-ThriveLensWrongPasswordProbe -ExitCode 2 -PrivateStandardOutput '' -PrivateStandardError $hostileDiagnostic -ExpectedPasswordFile $wrongPasswordPath -ServerUsableAfterProbe $true} 'WRONG_PASSWORD_PROBE_UNRELATED_FAILURE') 'WRONG_PASSWORD_HOSTILE_DIAGNOSTIC_REJECTED'
 }
 foreach($invalidExpectedPath in @(
  '/run/thrivelens-r0-wrong-0123456789ABCDEF0123456789abcdef.pgpass',
  '/run/thrivelens-r0-auth-0123456789abcdef0123456789abcdef.pgpass',
  ($wrongPasswordPath+'.extra'),($wrongPasswordPath+"`n")
 )){
  $invalidPathDiagnostic=$authError+"`npassword retrieved from file `"$invalidExpectedPath`""
  A (Test-ThrowsExact {Resolve-ThriveLensWrongPasswordProbe -ExitCode 2 -PrivateStandardOutput '' -PrivateStandardError $invalidPathDiagnostic -ExpectedPasswordFile $invalidExpectedPath -ServerUsableAfterProbe $true} 'WRONG_PASSWORD_PROBE_UNRELATED_FAILURE') 'WRONG_PASSWORD_EXPECTED_PATH_REJECTED'
 }
 A (Test-ThrowsExact {Resolve-ThriveLensWrongPasswordProbe -ExitCode 2 -PrivateStandardOutput '' -PrivateStandardError ($authError+"`n"+$passwordFileError) -ExpectedPasswordFile $wrongPasswordPath -ServerUsableAfterProbe $false} 'WRONG_PASSWORD_SERVER_USABILITY_UNVERIFIED') 'WRONG_PASSWORD_SERVER_UNUSABLE_REJECTED'
 $secretValue=$null
 try{
  $secretPath=[IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables([string]$manifest.wsl_fallback.host_password_file))
  $secretValue=Read-ThriveLensPostgresBootstrapSecret -Path $secretPath
  A ($secretValue -cmatch '^[A-Za-z0-9_-]{43,128}$') 'EXECUTABLE_PROTECTED_SECRET_READER'
 }finally{$secretValue=$null;Remove-Variable -Name secretValue -ErrorAction SilentlyContinue}
 $budget=[ThriveLens.WslSecurityV2.OutputBudget]::new(8);$sinkA=[ThriveLens.WslSecurityV2.BoundedCaptureStream]::new($budget);$sinkB=[ThriveLens.WslSecurityV2.BoundedCaptureStream]::new($budget)
 try{$sinkA.Write([byte[]](1,2,3,4),0,4);$sinkB.Write([byte[]](5,6,7,8),0,4);try{$sinkA.Write([byte[]](9),0,1)}catch{};A ($budget.Exceeded -and ($sinkA.Length+$sinkB.Length) -eq 8) 'EXECUTABLE_SHARED_OUTPUT_CAP'}finally{$sinkA.Dispose();$sinkB.Dispose()}
 A ((Resolve-ThriveLensClusterProbe -ExistsExitCode 1 -PathPolicyValid $false -VersionExitCode 1 -VersionOutput '' -ControlExitCode 1 -ChecksumsEnabled $false) -ceq 'ABSENT') 'CLUSTER_CLASSIFIER_ABSENT'
 A ((Resolve-ThriveLensClusterProbe -ExistsExitCode 0 -PathPolicyValid $true -VersionExitCode 0 -VersionOutput '17' -ControlExitCode 0 -ChecksumsEnabled $true) -ceq 'VALID') 'CLUSTER_CLASSIFIER_VALID'
 A ((Resolve-ThriveLensClusterProbe -ExistsExitCode 0 -PathPolicyValid $true -VersionExitCode 0 -VersionOutput '16' -ControlExitCode 0 -ChecksumsEnabled $true) -ceq 'PARTIAL_OR_INVALID') 'CLUSTER_CLASSIFIER_PARTIAL'
 A ($module -notmatch 'Resolve-ThriveLens(?:ChildOutcome|StartChildExit|PreTokenStartObservation)' -and $runtimeModule -notmatch 'Resolve-ThriveLens(?:StartChildFailure|RuntimeFailureOutcome)') 'OLD_CHILD_AND_PRETOKEN_POLICY_REMOVED'
 foreach($interCycleCode in @('RESOURCE_INTER_CYCLE_MEMORY_NOT_SETTLED','RESOURCE_INTER_CYCLE_MEMORY_MEASUREMENT_UNAVAILABLE')){$interCycleOutcome=Resolve-ThriveLensRuntimeCleanupOutcome -OriginalCode $interCycleCode -OriginalExitCode 2 -CleanupRequired $false -CleanupAuthorityVerified $true -CredentialCleanupRequired $true -CredentialRemoveFailed $false -CredentialAbsenceVerified $true -IdentityChanged $false -PostgresStopFailed $false -DistroTerminateFailed $false -DistroAbsenceCheckFailed $false -HostAbsenceCheckFailed $false -DistroAbsent $true -HostAbsent $true -LockReleaseFailed $false;A ($interCycleOutcome.Status -ceq 'BLOCKED' -and $interCycleOutcome.Code -ceq $interCycleCode -and $interCycleOutcome.OriginalCode -ceq $interCycleCode -and $interCycleOutcome.ExitCode -eq 2 -and $interCycleOutcome.CleanupVerified -and @($interCycleOutcome.FailureStages) -ccontains 'RESOURCE_GATE') 'INTER_CYCLE_MEMORY_BLOCKED_COMPOSITION'}
 foreach($safeCredentialFailure in @('WSL_COMMAND_TIMEOUT','WSL_OUTPUT_LIMIT_EXCEEDED','WSL_OUTPUT_DRAIN_INCOMPLETE','WSL_PROCESS_START_FAILED')){A (Test-ThriveLensCredentialAbsenceProbeAllowed -FailureCode $safeCredentialFailure) 'CREDENTIAL_CONTAINED_REMOVE_FAILURE_ALLOWS_ABSENCE_PROBE'}
 foreach($unsafeCredentialFailure in @('WSL_GUARDED_COMMAND_CONTAINMENT_FAILED','WSL_CLEANUP_IDENTITY_CHANGED','LIFECYCLE_LOCK_OWNERSHIP_REQUIRED','arbitrary secret text')){A (-not (Test-ThriveLensCredentialAbsenceProbeAllowed -FailureCode $unsafeCredentialFailure)) 'CREDENTIAL_UNSAFE_REMOVE_FAILURE_BLOCKS_ABSENCE_PROBE'}
 foreach($stopAuthorityCode in @('POSTGRES_STOP_FAILED','POSTGRES_CLUSTER_STILL_RUNNING','WSL_COMMAND_TIMEOUT')){A (Test-ThriveLensCleanupFailurePreservesIdentityAuthority -Stage 'POSTGRES_STOP' -FailureCode $stopAuthorityCode) 'POSTGRES_STOP_OPERATIONAL_FAILURE_RETAINS_OLD_TOKEN_AUTHORITY'}
 foreach($stopAbsenceCode in @('POSTGRES_CLUSTER_STILL_RUNNING','POSTGRES_LISTENER_STILL_PRESENT','POSTGRES_PROCESS_STILL_PRESENT')){$stopAbsenceOutcome=Resolve-ThriveLensRuntimeCleanupOutcome -OriginalCode $stopAbsenceCode -OriginalExitCode 3 -CleanupRequired $true -CleanupAuthorityVerified $true -CredentialCleanupRequired $false -CredentialRemoveFailed $false -CredentialAbsenceVerified $true -IdentityChanged $false -PostgresStopFailed $true -DistroTerminateFailed $false -DistroAbsenceCheckFailed $false -HostAbsenceCheckFailed $false -DistroAbsent $true -HostAbsent $true -LockReleaseFailed $false;A ($stopAbsenceOutcome.OriginalCode -ceq $stopAbsenceCode -and $stopAbsenceOutcome.CleanupVerified -and @($stopAbsenceOutcome.FailureStages) -contains 'POSTGRES_STOP' -and (Test-ThriveLensCleanupFailurePreservesIdentityAuthority -Stage 'POSTGRES_STOP' -FailureCode $stopAbsenceCode)) 'POSTGRES_STOP_ABSENCE_CODE_COMPOSED_AND_PRESERVED'}
 foreach($terminateAuthorityCode in @('WSL_DISTRO_TERMINATE_FAILED','WSL_COMMAND_TIMEOUT')){A (Test-ThriveLensCleanupFailurePreservesIdentityAuthority -Stage 'DISTRO_TERMINATE' -FailureCode $terminateAuthorityCode) 'TERMINATE_OPERATIONAL_FAILURE_RETAINS_OLD_TOKEN_AUTHORITY'}
 foreach($distroAbsenceAuthorityCode in @('WSL_RUNNING_STATE_UNAVAILABLE','WSL_DISTRO_STILL_RUNNING')){A (Test-ThriveLensCleanupFailurePreservesIdentityAuthority -Stage 'DISTRO_ABSENCE' -FailureCode $distroAbsenceAuthorityCode) 'DISTRO_ABSENCE_OPERATIONAL_FAILURE_RETAINS_OLD_TOKEN_AUTHORITY'}
 foreach($hostAbsenceAuthorityCode in @('HOST_LISTENER_MEASUREMENT_UNAVAILABLE','HOST_POSTGRES_LISTENER_STILL_PRESENT','HOST_PORTPROXY_MEASUREMENT_UNAVAILABLE','HOST_PORTPROXY_STILL_PRESENT')){A (Test-ThriveLensCleanupFailurePreservesIdentityAuthority -Stage 'HOST_ABSENCE' -FailureCode $hostAbsenceAuthorityCode) 'HOST_ABSENCE_OPERATIONAL_FAILURE_RETAINS_OLD_TOKEN_AUTHORITY'}
 $distroAbsenceFailure=Resolve-ThriveLensDistroCleanupFailure -FailureCode 'WSL_DISTRO_STILL_RUNNING';A ($distroAbsenceFailure.Stage -ceq 'DISTRO_ABSENCE' -and $distroAbsenceFailure.IdentityAuthorityPreserved) 'DISTRO_ABSENCE_FAILURE_EXACTLY_CLASSIFIED'
 $hostAbsenceFailure=Resolve-ThriveLensDistroCleanupFailure -FailureCode 'HOST_POSTGRES_LISTENER_STILL_PRESENT';A ($hostAbsenceFailure.Stage -ceq 'HOST_ABSENCE' -and $hostAbsenceFailure.IdentityAuthorityPreserved) 'HOST_ABSENCE_FAILURE_EXACTLY_CLASSIFIED'
 foreach($unsafeDistroCleanupCode in @('WSL_CLEANUP_IDENTITY_CHANGED','LIFECYCLE_LOCK_OWNERSHIP_REQUIRED','arbitrary secret text')){$unsafeDistroCleanup=Resolve-ThriveLensDistroCleanupFailure -FailureCode $unsafeDistroCleanupCode;A (-not $unsafeDistroCleanup.IdentityAuthorityPreserved) 'DISTRO_CLEANUP_IDENTITY_OR_UNKNOWN_DEFAULT_DENY'}
 foreach($identityFailureCode in @('WSL_CLEANUP_IDENTITY_CHANGED','LIFECYCLE_LOCK_OWNERSHIP_REQUIRED','WSL_STORAGE_REPARSE_REJECTED','arbitrary secret text')){A (-not (Test-ThriveLensCleanupFailurePreservesIdentityAuthority -Stage 'POSTGRES_STOP' -FailureCode $identityFailureCode)) 'POSTGRES_STOP_IDENTITY_OR_UNKNOWN_FAILURE_DEFAULT_DENY';A (-not (Test-ThriveLensCleanupFailurePreservesIdentityAuthority -Stage 'DISTRO_TERMINATE' -FailureCode $identityFailureCode)) 'TERMINATE_IDENTITY_OR_UNKNOWN_FAILURE_DEFAULT_DENY'}
 $credentialClean=Resolve-ThriveLensCredentialCleanupResult -RemoveSucceeded $true -AbsenceAttempted $true -AbsenceVerified $true -RootFailureCode $null;A ($credentialClean.CredentialAbsenceVerified -and $null -eq $credentialClean.FailureCode -and $null -eq $credentialClean.RootFailureCode -and $credentialClean.FailureStages.Count -eq 0) 'CREDENTIAL_CLEANUP_SUCCESS_CLASSIFIED'
 $credentialRemoveAnomaly=Resolve-ThriveLensCredentialCleanupResult -RemoveSucceeded $false -AbsenceAttempted $true -AbsenceVerified $true -RootFailureCode 'WSL_COMMAND_TIMEOUT';A ($credentialRemoveAnomaly.CredentialAbsenceVerified -and $credentialRemoveAnomaly.FailureCode -ceq 'AUTH_FILE_CLEANUP_REMOVE_FAILED' -and $credentialRemoveAnomaly.RootFailureCode -ceq 'WSL_COMMAND_TIMEOUT' -and @($credentialRemoveAnomaly.FailureStages) -ceq 'CREDENTIAL_REMOVE') 'CREDENTIAL_REMOVE_FAILURE_WITH_ABSENCE_CLASSIFIED'
 $credentialAbsenceMissing=Resolve-ThriveLensCredentialCleanupResult -RemoveSucceeded $true -AbsenceAttempted $true -AbsenceVerified $false -RootFailureCode 'WSL_COMMAND_TIMEOUT';A (-not $credentialAbsenceMissing.CredentialAbsenceVerified -and $credentialAbsenceMissing.FailureCode -ceq 'AUTH_FILE_CLEANUP_ABSENCE_UNVERIFIED' -and $credentialAbsenceMissing.RootFailureCode -ceq 'WSL_COMMAND_TIMEOUT' -and @($credentialAbsenceMissing.FailureStages) -contains 'CREDENTIAL_ABSENCE') 'CREDENTIAL_ABSENCE_FAILURE_CLASSIFIED'
 $credentialContainmentBlocked=Resolve-ThriveLensCredentialCleanupResult -RemoveSucceeded $false -AbsenceAttempted $false -AbsenceVerified $false -RootFailureCode 'WSL_CLEANUP_IDENTITY_CHANGED';A (-not $credentialContainmentBlocked.CredentialAbsenceVerified -and $credentialContainmentBlocked.RootFailureCode -ceq 'WSL_CLEANUP_IDENTITY_CHANGED' -and @($credentialContainmentBlocked.FailureStages) -contains 'CREDENTIAL_REMOVE' -and @($credentialContainmentBlocked.FailureStages) -contains 'CREDENTIAL_ABSENCE') 'CREDENTIAL_CONTAINMENT_FAILURE_NO_FOLLOW_ON_CLASSIFIED'
 A ((Resolve-ThriveLensCredentialFailureCode -PrimaryOperationCode 'SCRAM_AUTH_PROBE_FAILED' -RootFailureCode 'WSL_CLEANUP_IDENTITY_CHANGED' -CleanupCode 'AUTH_FILE_CLEANUP_ABSENCE_UNVERIFIED') -ceq 'SCRAM_AUTH_PROBE_FAILED') 'CREDENTIAL_CAUSE_PRIMARY_WINS'
 A ((Resolve-ThriveLensCredentialFailureCode -PrimaryOperationCode $null -RootFailureCode 'WSL_CLEANUP_IDENTITY_CHANGED' -CleanupCode 'AUTH_FILE_CLEANUP_ABSENCE_UNVERIFIED') -ceq 'WSL_CLEANUP_IDENTITY_CHANGED') 'CREDENTIAL_CAUSE_ROOT_WINS_WITHOUT_PRIMARY'
 A ((Resolve-ThriveLensCredentialFailureCode -PrimaryOperationCode $null -RootFailureCode $null -CleanupCode 'AUTH_FILE_CLEANUP_ABSENCE_UNVERIFIED') -ceq 'AUTH_FILE_CLEANUP_ABSENCE_UNVERIFIED') 'CREDENTIAL_CAUSE_CLEANUP_FALLBACK'
 A ((Resolve-ThriveLensCredentialFailureCode -PrimaryOperationCode $null -RootFailureCode 'raw private detail' -CleanupCode 'AUTH_FILE_CLEANUP_ABSENCE_UNVERIFIED') -ceq 'RUNTIME_TEST_INTERNAL_ERROR') 'CREDENTIAL_CAUSE_UNKNOWN_SANITIZED_DEFAULT_DENY'
 $gracefulRecovered=Resolve-ThriveLensRuntimeCleanupOutcome -OriginalCode 'SCRAM_AUTH_PROBE_FAILED' -OriginalExitCode 2 -CleanupRequired $true -CleanupAuthorityVerified $true -CredentialCleanupRequired $false -CredentialRemoveFailed $false -CredentialAbsenceVerified $true -IdentityChanged $false -PostgresStopFailed $true -DistroTerminateFailed $false -DistroAbsenceCheckFailed $false -HostAbsenceCheckFailed $false -DistroAbsent $true -HostAbsent $true -LockReleaseFailed $false
 A ($gracefulRecovered.CleanupVerified -and $gracefulRecovered.Status -ceq 'BLOCKED' -and $gracefulRecovered.Code -ceq 'SCRAM_AUTH_PROBE_FAILED' -and @($gracefulRecovered.FailureStages) -contains 'POSTGRES_STOP') 'RUNTIME_GRACEFUL_FAILURE_FINAL_CONTAINMENT_TRUTH'
 $terminateRecovered=Resolve-ThriveLensRuntimeCleanupOutcome -OriginalCode 'SCRAM_AUTH_PROBE_FAILED' -OriginalExitCode 2 -CleanupRequired $true -CleanupAuthorityVerified $true -CredentialCleanupRequired $false -CredentialRemoveFailed $false -CredentialAbsenceVerified $true -IdentityChanged $false -PostgresStopFailed $false -DistroTerminateFailed $true -DistroAbsenceCheckFailed $false -HostAbsenceCheckFailed $false -DistroAbsent $true -HostAbsent $true -LockReleaseFailed $false
 A ($terminateRecovered.CleanupVerified -and @($terminateRecovered.FailureStages) -contains 'DISTRO_TERMINATE') 'RUNTIME_TERMINATE_ANOMALY_FINAL_CONTAINMENT_TRUTH'
 $distroAbsenceRecovered=Resolve-ThriveLensRuntimeCleanupOutcome -OriginalCode 'SCRAM_AUTH_PROBE_FAILED' -OriginalExitCode 2 -CleanupRequired $true -CleanupAuthorityVerified $true -CredentialCleanupRequired $false -CredentialRemoveFailed $false -CredentialAbsenceVerified $true -IdentityChanged $false -PostgresStopFailed $false -DistroTerminateFailed $false -DistroAbsenceCheckFailed $true -HostAbsenceCheckFailed $false -DistroAbsent $true -HostAbsent $true -LockReleaseFailed $false
 A ($distroAbsenceRecovered.CleanupVerified -and @($distroAbsenceRecovered.FailureStages) -contains 'DISTRO_ABSENCE' -and @($distroAbsenceRecovered.FailureStages) -notcontains 'DISTRO_TERMINATE') 'RUNTIME_RECOVERED_DISTRO_ABSENCE_EXACT_STAGE'
 $hostAbsenceRecovered=Resolve-ThriveLensRuntimeCleanupOutcome -OriginalCode 'SCRAM_AUTH_PROBE_FAILED' -OriginalExitCode 2 -CleanupRequired $true -CleanupAuthorityVerified $true -CredentialCleanupRequired $false -CredentialRemoveFailed $false -CredentialAbsenceVerified $true -IdentityChanged $false -PostgresStopFailed $false -DistroTerminateFailed $false -DistroAbsenceCheckFailed $false -HostAbsenceCheckFailed $true -DistroAbsent $true -HostAbsent $true -LockReleaseFailed $false
 A ($hostAbsenceRecovered.CleanupVerified -and @($hostAbsenceRecovered.FailureStages) -contains 'HOST_ABSENCE' -and @($hostAbsenceRecovered.FailureStages) -notcontains 'DISTRO_TERMINATE') 'RUNTIME_RECOVERED_HOST_ABSENCE_EXACT_STAGE'
 $hostUnverified=Resolve-ThriveLensRuntimeCleanupOutcome -OriginalCode 'SCRAM_AUTH_PROBE_FAILED' -OriginalExitCode 2 -CleanupRequired $true -CleanupAuthorityVerified $true -CredentialCleanupRequired $false -CredentialRemoveFailed $false -CredentialAbsenceVerified $true -IdentityChanged $false -PostgresStopFailed $false -DistroTerminateFailed $false -DistroAbsenceCheckFailed $false -HostAbsenceCheckFailed $false -DistroAbsent $true -HostAbsent $false -LockReleaseFailed $false
 A (-not $hostUnverified.CleanupVerified -and $hostUnverified.Status -ceq 'ERROR' -and $hostUnverified.Code -ceq 'RUNTIME_CLEANUP_FAILED' -and @($hostUnverified.FailureStages) -contains 'HOST_ABSENCE') 'RUNTIME_FINAL_HOST_ABSENCE_REQUIRED'
 $identityChangedOutcome=Resolve-ThriveLensRuntimeCleanupOutcome -OriginalCode 'SCRAM_AUTH_PROBE_FAILED' -OriginalExitCode 2 -CleanupRequired $true -CleanupAuthorityVerified $true -CredentialCleanupRequired $false -CredentialRemoveFailed $false -CredentialAbsenceVerified $true -IdentityChanged $true -PostgresStopFailed $false -DistroTerminateFailed $false -DistroAbsenceCheckFailed $false -HostAbsenceCheckFailed $false -DistroAbsent $true -HostAbsent $true -LockReleaseFailed $false
 A (-not $identityChangedOutcome.CleanupVerified -and $identityChangedOutcome.Code -ceq 'RUNTIME_CLEANUP_IDENTITY_CHANGED' -and @($identityChangedOutcome.FailureStages) -contains 'IDENTITY') 'RUNTIME_IDENTITY_DRIFT_FATAL'
 $credentialUnverifiedOutcome=Resolve-ThriveLensRuntimeCleanupOutcome -OriginalCode 'AUTH_FILE_CLEANUP_ABSENCE_UNVERIFIED' -OriginalExitCode 3 -CleanupRequired $true -CleanupAuthorityVerified $true -CredentialCleanupRequired $true -CredentialRemoveFailed $false -CredentialAbsenceVerified $false -IdentityChanged $false -PostgresStopFailed $false -DistroTerminateFailed $false -DistroAbsenceCheckFailed $false -HostAbsenceCheckFailed $false -DistroAbsent $true -HostAbsent $true -LockReleaseFailed $false
 A (-not $credentialUnverifiedOutcome.CleanupVerified -and $credentialUnverifiedOutcome.Code -ceq 'RUNTIME_CLEANUP_FAILED' -and $credentialUnverifiedOutcome.OriginalCode -ceq 'AUTH_FILE_CLEANUP_ABSENCE_UNVERIFIED') 'RUNTIME_CREDENTIAL_ABSENCE_REQUIRED'
 $primaryWithRemoveAnomaly=Resolve-ThriveLensRuntimeCleanupOutcome -OriginalCode 'SCRAM_AUTH_PROBE_FAILED' -OriginalExitCode 3 -CleanupRequired $true -CleanupAuthorityVerified $true -CredentialCleanupRequired $true -CredentialRemoveFailed $true -CredentialAbsenceVerified $true -IdentityChanged $false -PostgresStopFailed $false -DistroTerminateFailed $false -DistroAbsenceCheckFailed $false -HostAbsenceCheckFailed $false -DistroAbsent $true -HostAbsent $true -LockReleaseFailed $false
 A ($primaryWithRemoveAnomaly.OriginalCode -ceq 'SCRAM_AUTH_PROBE_FAILED' -and $primaryWithRemoveAnomaly.ExitCode -eq 3 -and $primaryWithRemoveAnomaly.CleanupVerified -and @($primaryWithRemoveAnomaly.FailureStages) -contains 'PROBE' -and @($primaryWithRemoveAnomaly.FailureStages) -contains 'CREDENTIAL_REMOVE') 'RUNTIME_PRIMARY_FAILURE_SURVIVES_CREDENTIAL_REMOVE_ANOMALY'
 $primaryWithAbsenceFailure=Resolve-ThriveLensRuntimeCleanupOutcome -OriginalCode 'WRONG_PASSWORD_PROBE_UNRELATED_FAILURE' -OriginalExitCode 3 -CleanupRequired $true -CleanupAuthorityVerified $true -CredentialCleanupRequired $true -CredentialRemoveFailed $true -CredentialAbsenceVerified $false -IdentityChanged $false -PostgresStopFailed $false -DistroTerminateFailed $false -DistroAbsenceCheckFailed $false -HostAbsenceCheckFailed $false -DistroAbsent $true -HostAbsent $true -LockReleaseFailed $false
 A ($primaryWithAbsenceFailure.OriginalCode -ceq 'WRONG_PASSWORD_PROBE_UNRELATED_FAILURE' -and -not $primaryWithAbsenceFailure.CleanupVerified -and @($primaryWithAbsenceFailure.FailureStages) -contains 'CREDENTIAL_REMOVE' -and @($primaryWithAbsenceFailure.FailureStages) -contains 'CREDENTIAL_ABSENCE') 'RUNTIME_PRIMARY_FAILURE_SURVIVES_CREDENTIAL_ABSENCE_FAILURE'
 $primaryWithIdentityCredentialFailure=Resolve-ThriveLensRuntimeCleanupOutcome -OriginalCode 'SCRAM_AUTH_PROBE_FAILED' -OriginalExitCode 3 -CleanupRequired $true -CleanupAuthorityVerified $true -CredentialCleanupRequired $true -CredentialRemoveFailed $true -CredentialRootFailureCode 'WSL_CLEANUP_IDENTITY_CHANGED' -CredentialAbsenceVerified $false -IdentityChanged $false -PostgresStopFailed $false -DistroTerminateFailed $false -DistroAbsenceCheckFailed $false -HostAbsenceCheckFailed $false -DistroAbsent $true -HostAbsent $true -LockReleaseFailed $false
 A ($primaryWithIdentityCredentialFailure.OriginalCode -ceq 'SCRAM_AUTH_PROBE_FAILED' -and -not $primaryWithIdentityCredentialFailure.CleanupVerified -and @($primaryWithIdentityCredentialFailure.FailureStages) -contains 'IDENTITY' -and @($primaryWithIdentityCredentialFailure.FailureStages) -contains 'CREDENTIAL_ABSENCE') 'RUNTIME_CREDENTIAL_ROOT_CAUSE_COMPOSED_WITH_PRIMARY'
 $rootOnlyCode=Resolve-ThriveLensCredentialFailureCode -PrimaryOperationCode $null -RootFailureCode 'WSL_CLEANUP_IDENTITY_CHANGED' -CleanupCode 'AUTH_FILE_CLEANUP_ABSENCE_UNVERIFIED'
 $rootOnlyOutcome=Resolve-ThriveLensRuntimeCleanupOutcome -OriginalCode $rootOnlyCode -OriginalExitCode 3 -CleanupRequired $true -CleanupAuthorityVerified $true -CredentialCleanupRequired $true -CredentialRemoveFailed $true -CredentialRootFailureCode 'WSL_CLEANUP_IDENTITY_CHANGED' -CredentialAbsenceVerified $false -IdentityChanged $false -PostgresStopFailed $false -DistroTerminateFailed $false -DistroAbsenceCheckFailed $false -HostAbsenceCheckFailed $false -DistroAbsent $true -HostAbsent $true -LockReleaseFailed $false
 A ($rootOnlyOutcome.OriginalCode -ceq 'WSL_CLEANUP_IDENTITY_CHANGED' -and -not $rootOnlyOutcome.CleanupVerified -and @($rootOnlyOutcome.FailureStages) -contains 'IDENTITY' -and @($rootOnlyOutcome.FailureStages) -contains 'CREDENTIAL_ABSENCE') 'RUNTIME_CREDENTIAL_ROOT_CAUSE_BECOMES_PRIMARY_WHEN_ALONE'
 $lockReleaseOutcome=Resolve-ThriveLensRuntimeCleanupOutcome -OriginalCode 'SCRAM_AUTH_PROBE_FAILED' -OriginalExitCode 2 -CleanupRequired $true -CleanupAuthorityVerified $true -CredentialCleanupRequired $false -CredentialRemoveFailed $false -CredentialAbsenceVerified $true -IdentityChanged $false -PostgresStopFailed $false -DistroTerminateFailed $false -DistroAbsenceCheckFailed $false -HostAbsenceCheckFailed $false -DistroAbsent $true -HostAbsent $true -LockReleaseFailed $true
 A ($lockReleaseOutcome.CleanupVerified -and $lockReleaseOutcome.Status -ceq 'ERROR' -and $lockReleaseOutcome.Code -ceq 'RUNTIME_LOCK_RELEASE_FAILED' -and @($lockReleaseOutcome.FailureStages) -contains 'LOCK_RELEASE') 'RUNTIME_LOCK_RELEASE_SEPARATE_FROM_PHYSICAL_CONTAINMENT'
 $containmentBlocked=Resolve-ThriveLensCleanupContainmentPolicy -FailureCode 'WSL_GUARDED_COMMAND_CONTAINMENT_FAILED' -SameTokenContainmentReverified $false
 A ($containmentBlocked.RequiresRecontainment -and -not $containmentBlocked.AllowGuestCleanup -and $containmentBlocked.Fatal) 'CLEANUP_CONTAINMENT_FAILURE_BLOCKS_GUEST_CLEANUP'
 $containmentRecovered=Resolve-ThriveLensCleanupContainmentPolicy -FailureCode 'WSL_GUARDED_COMMAND_CONTAINMENT_FAILED' -SameTokenContainmentReverified $true
 A ($containmentRecovered.RequiresRecontainment -and $containmentRecovered.AllowGuestCleanup -and $containmentRecovered.Fatal) 'CLEANUP_CONTAINMENT_REVERIFY_REQUIRED'
 $unknownContainment=Resolve-ThriveLensCleanupContainmentPolicy -FailureCode 'not-sanitized' -SameTokenContainmentReverified $true
 A ($unknownContainment.RequiresRecontainment -and -not $unknownContainment.AllowGuestCleanup -and $unknownContainment.Fatal) 'CLEANUP_UNKNOWN_FAILURE_DEFAULT_DENY'
 $dataRoot='/var/lib/thrivelens/postgresql/r0';$logRoot='/var/log/thrivelens/postgresql/r0';$treeLimit=[int64]134217728;$stagingRoot='/var/lib/thrivelens/postgresql/.r0-staging-0123456789abcdef0123456789abcdef'
 $dataPolicy=Resolve-ThriveLensLinuxTreeRootPolicy -Root $dataRoot -DataRoot $dataRoot -LogRoot $logRoot -MaximumBytes $treeLimit
 A ($dataPolicy.Kind -ceq 'DATA' -and $dataPolicy.MaximumBytes -eq $treeLimit) 'TREE_ROOT_DATA_ACCEPTED'
 $logPolicy=Resolve-ThriveLensLinuxTreeRootPolicy -Root $logRoot -DataRoot $dataRoot -LogRoot $logRoot -MaximumBytes $treeLimit
 A ($logPolicy.Kind -ceq 'LOG' -and $logPolicy.MaximumBytes -eq $treeLimit) 'TREE_ROOT_LOG_ACCEPTED'
 $stagingPolicy=Resolve-ThriveLensLinuxTreeRootPolicy -Root $stagingRoot -DataRoot $dataRoot -LogRoot $logRoot -MaximumBytes $treeLimit
 A ($stagingPolicy.Kind -ceq 'STAGING' -and $stagingPolicy.MaximumBytes -eq $treeLimit) 'TREE_ROOT_STAGING_ACCEPTED'
 A (Test-ThrowsExact {Assert-ThriveLensLinuxTreePolicy -Root $stagingRoot} 'LINUX_TREE_GUARD_REQUIRED') 'POST_MUTATION_TREE_INSPECTION_REQUIRES_CONTAINMENT_GUARD'
 A (Test-ThrowsExact {Resolve-ThriveLensLinuxTreeRootPolicy -Root '/tmp/r0' -DataRoot $dataRoot -LogRoot $logRoot -MaximumBytes $treeLimit} 'LINUX_TREE_ROOT_CONTRACT_MISMATCH') 'TREE_ROOT_OUTSIDE_REJECTED'
 A (Test-ThrowsExact {Resolve-ThriveLensLinuxTreeRootPolicy -Root '/var/lib/thrivelens/postgresql/../r0' -DataRoot $dataRoot -LogRoot $logRoot -MaximumBytes $treeLimit} 'LINUX_TREE_ROOT_CONTRACT_MISMATCH') 'TREE_ROOT_MALFORMED_REJECTED'
 A (Test-ThrowsExact {Resolve-ThriveLensLinuxTreeRootPolicy -Root $stagingRoot -DataRoot $dataRoot -LogRoot $logRoot -MaximumBytes 134217729} 'LINUX_TREE_LIMIT_CONTRACT_MISMATCH') 'TREE_ROOT_OVERSIZE_LIMIT_REJECTED'
 $proxyListen=Resolve-ThriveLensPortProxyMapping -Source '127.0.0.1/55432' -Destination '127.0.0.1/12345';A ($proxyListen.ListenPort -eq 55432 -and $proxyListen.ConnectPort -eq 12345) 'PORTPROXY_LISTEN_TARGET_PARSED'
 $proxyConnect=Resolve-ThriveLensPortProxyMapping -Source '127.0.0.1/12345' -Destination '127.0.0.1/55432';A ($proxyConnect.ListenPort -eq 12345 -and $proxyConnect.ConnectPort -eq 55432) 'PORTPROXY_CONNECT_TARGET_PARSED'
 A (Test-ThrowsExact {Resolve-ThriveLensPortProxyMapping -Source 'malformed' -Destination '127.0.0.1/55432'} 'HOST_PORTPROXY_MEASUREMENT_UNAVAILABLE') 'PORTPROXY_MALFORMED_REJECTED'
 $holderInfo=[Diagnostics.ProcessStartInfo]::new();$holderInfo.FileName=(Join-Path $PSHOME 'pwsh.exe');$holderInfo.UseShellExecute=$false;$holderInfo.RedirectStandardOutput=$true;$holderInfo.CreateNoWindow=$true
 $null=$holderInfo.ArgumentList.Add('-NoProfile');$null=$holderInfo.ArgumentList.Add('-Command');$null=$holderInfo.ArgumentList.Add('$m=[Threading.Mutex]::new($false,''Local\ThriveLens-R0-PostgreSQL-Lifecycle'');$null=$m.WaitOne();[Console]::Out.WriteLine(''READY'');Start-Sleep -Seconds 3;$m.ReleaseMutex();$m.Dispose()')
 $holder=[Diagnostics.Process]::Start($holderInfo)
 $holderReaped=$false
 try{
  $ready=$null;$readyTask=$holder.StandardOutput.ReadLineAsync();$readyObserved=$false
  try{if($readyTask.Wait(5000)){$ready=$readyTask.GetAwaiter().GetResult();$readyObserved=$ready -ceq 'READY'}}catch{}
  $lockCode=$null
  if($readyObserved){try{$probeLock=Enter-ThriveLensLifecycleLock -TimeoutSeconds 1;Exit-ThriveLensLifecycleLock -Mutex $probeLock}catch{$lockCode=$_.Exception.Message}}
 A ($readyObserved -and $lockCode -ceq 'LIFECYCLE_LOCK_TIMEOUT') 'EXECUTABLE_LOCK_TIMEOUT'
 }finally{
  try{
   $holderReaped=$holder.WaitForExit(5000)
   if(-not $holderReaped){
    try{$holder.Kill($true)}catch{if(-not $holder.HasExited){throw}}
    $holderReaped=$holder.WaitForExit(5000)
   }
  }catch{$holderReaped=$false}
  $holder.Dispose()
 }
 A $holderReaped 'EXECUTABLE_LOCK_HOLDER_REAP'
 $abandonInfo=[Diagnostics.ProcessStartInfo]::new();$abandonInfo.FileName=(Join-Path $PSHOME 'pwsh.exe');$abandonInfo.UseShellExecute=$false;$abandonInfo.RedirectStandardOutput=$true;$abandonInfo.CreateNoWindow=$true
 $null=$abandonInfo.ArgumentList.Add('-NoProfile');$null=$abandonInfo.ArgumentList.Add('-Command');$null=$abandonInfo.ArgumentList.Add('$m=[Threading.Mutex]::new($false,''Local\ThriveLens-R0-PostgreSQL-Lifecycle'');$null=$m.WaitOne();[Console]::Out.WriteLine(''READY'');Start-Sleep -Milliseconds 750;[Environment]::Exit(0)')
 $abandon=[Diagnostics.Process]::Start($abandonInfo);$abandonedRecovered=$false
 try{
  $abandonReadyTask=$abandon.StandardOutput.ReadLineAsync();$abandonReady=$abandonReadyTask.Wait(5000) -and $abandonReadyTask.GetAwaiter().GetResult() -ceq 'READY'
  if($abandonReady){$recoveredLock=Enter-ThriveLensLifecycleLock -TimeoutSeconds 2;try{$abandonedRecovered=$true}finally{Exit-ThriveLensLifecycleLock -Mutex $recoveredLock}}
  $abandonExited=$abandon.WaitForExit(5000);$abandonedRecovered=$abandonedRecovered -and $abandonExited
 }finally{if(-not $abandon.HasExited){try{$abandon.Kill($true);$null=$abandon.WaitForExit(5000)}catch{}};$abandon.Dispose()}
 A $abandonedRecovered 'EXECUTABLE_ABANDONED_LOCK_RECOVERY'
 $initialize=Get-Content (Join-Path $PSScriptRoot 'initialize.ps1') -Raw
 $stagingGuard='Assert-ThriveLensLinuxTreePolicy -Root $staging -IdentityToken $cleanupIdentityToken -LifecycleLock $lifecycleLock';$firstStagingGuard=$initialize.IndexOf($stagingGuard);$lastStagingGuard=$initialize.LastIndexOf($stagingGuard);$activationAttempted=$initialize.IndexOf('$activationAttempted=$true');$activationMove=$initialize.IndexOf('$move=Invoke-ThriveLensGuardedDistro');$rollbackDelete=$initialize.IndexOf('rm_tree(fd)')
 A ($initialize -match 'Read-ThriveLensPostgresBootstrapSecret\s+-Path\s+\$passwordPath') 'INITIALIZE_PROTECTED_SECRET_READER'
 A ($firstStagingGuard -ge 0 -and $activationMove -gt $firstStagingGuard) 'INITIALIZE_STAGING_GUARD_BEFORE_MOVE'
 A ($lastStagingGuard -gt $activationMove -and $rollbackDelete -gt $lastStagingGuard) 'INITIALIZE_STAGING_GUARD_BEFORE_ROLLBACK'
 $treeFunctionStart=$module.IndexOf('function Assert-ThriveLensLinuxTreePolicy');$treeFunctionEnd=$module.IndexOf('function Assert-ThriveLensLinuxPathPolicy',$treeFunctionStart);$treeFunctionBody=if($treeFunctionStart -ge 0 -and $treeFunctionEnd -gt $treeFunctionStart){$module.Substring($treeFunctionStart,$treeFunctionEnd-$treeFunctionStart)}else{''}
 A ($treeFunctionBody -match "Kind -ceq 'STAGING'.*LINUX_TREE_GUARD_REQUIRED" -and
    $treeFunctionBody -match 'Invoke-ThriveLensDistroProbe\s+`?\s*-Contract\s+\$Contract\s+`?\s*-IdentityToken\s+\$IdentityToken\s+`?\s*-LifecycleLock\s+\$LifecycleLock') 'POST_MUTATION_TREE_SUPERVISOR_IDENTITY_FENCED'
 A ($initialize -match "fdinfo/'\+str\(fd\)" -and $initialize -match 'mount_id\(parentfd\) != trustedmount' -and $initialize -match 'rootmount != trustedmount' -and $initialize -match 'mount_id\(child\) != rootmount' -and $initialize -match 'mount_id\(leaf\) != rootmount' -and $initialize -notmatch 'shutil\.rmtree') 'INITIALIZE_FD_RELATIVE_MOUNT_FENCED_ROLLBACK'
 A ($activationAttempted -ge 0 -and $activationAttempted -lt $activationMove -and $initialize -match 'if\(\$activationAttempted -or \$activated\)\{\$fatalCleanup=\$true\}') 'INITIALIZE_ACTIVATION_ATTEMPT_FATAL'
 A ($initialize -match '\$null -ne \$staging -and -not \$activationAttempted -and -not \$activated') 'INITIALIZE_NO_ROLLBACK_AFTER_ACTIVATION_ATTEMPT'
 A ($initialize -match '\$wslTouched=\$true' -and $initialize -match 'if\(\$cleanupIdentityReady -and \(\$wslTouched -or \$mutated -or \$activationAttempted\)\)') 'INITIALIZE_ALL_POST_PREFLIGHT_WSL_PATHS_CLEANED'
 $mutationMarker=$initialize.IndexOf('$mutated = $true');$directoryLoop=$initialize.IndexOf('foreach($directory');A ($mutationMarker -ge 0 -and $directoryLoop -gt $mutationMarker) 'INITIALIZE_MUTATION_TRACKED_BEFORE_DIRECTORY_CREATE'
 $validBranchStart=$initialize.IndexOf("if(`$clusterState -ceq 'VALID')");$validBranchEnd=$initialize.IndexOf("if(`$clusterState -cne 'ABSENT')",$validBranchStart);$validBranch=if($validBranchStart -ge 0 -and $validBranchEnd -gt $validBranchStart){$initialize.Substring($validBranchStart,$validBranchEnd-$validBranchStart)}else{''};A ($validBranch -match 'Stop-ThriveLensDistroAndVerify' -and $validBranch -match 'Assert-ThriveLensHostPortAbsent') 'INITIALIZE_IDEMPOTENT_CLEANUP'
 $startRaw=Get-Content (Join-Path $PSScriptRoot 'start.ps1') -Raw
 $startParsed=Get-ThriveLensParsedSource -Source $startRaw;$startAst=$startParsed.Ast;$startErrors=$startParsed.Errors
 A (Test-ThriveLensStartAdapterContract -Source $startRaw) 'START_IN_PROCESS_TRANSACTION_CONTRACT'
 A ($startRaw -notmatch 'Invoke-ThriveLensGuardedDistro|Assert-ThriveLensWslPackages|Get-ThriveLensWslClusterState') 'START_THIN_ADAPTER_NO_CORE_DUPLICATION'
 foreach($lifecycleFile in @('preflight.ps1','initialize.ps1','start.ps1','stop.ps1')){
  $lifecycleRaw=Get-Content (Join-Path $PSScriptRoot $lifecycleFile) -Raw
  $tokenIndex=$lifecycleRaw.IndexOf('Get-ThriveLensWslCleanupIdentityToken');$distroIndex=$lifecycleRaw.IndexOf('Assert-ThriveLensWslIdentity')
  A ($tokenIndex -ge 0 -and ($distroIndex -lt 0 -or $tokenIndex -lt $distroIndex)) ('IDENTITY_TOKEN_BEFORE_DISTRO_'+$lifecycleFile)
  $lifecycleParsed=Get-ThriveLensParsedSource -Source $lifecycleRaw
  $unguardedTerminate=@(Get-ThriveLensCommandAsts -Ast $lifecycleParsed.Ast -Name 'Stop-ThriveLensDistroAndVerify'|Where-Object{
   $_.Extent.Text -notmatch '-IdentityToken\s+\$[A-Za-z_][A-Za-z0-9_]*' -or $_.Extent.Text -notmatch '-LifecycleLock\s+\$[A-Za-z_][A-Za-z0-9_]*'
  })
  A ($unguardedTerminate.Count -eq 0) ('TERMINATE_TOKEN_ARGUMENTS_'+$lifecycleFile)
 }
 $stopRaw=Get-Content (Join-Path $PSScriptRoot 'stop.ps1') -Raw
 A ($stopRaw -match 'if\(\$null -ne \$lifecycleLock -and \$null -ne \$cleanupIdentityToken\)') 'STOP_LOCK_FAILURE_NEVER_TERMINATES'
 $stopFunctionStart=$module.IndexOf('function Stop-ThriveLensPostgresUnderLock');$stopFunctionEnd=$module.IndexOf('function Resolve-ThriveLensRuntimePublicCode',$stopFunctionStart);$stopFunctionBody=if($stopFunctionStart -ge 0 -and $stopFunctionEnd -gt $stopFunctionStart){$module.Substring($stopFunctionStart,$stopFunctionEnd-$stopFunctionStart)}else{''}
 A ($stopFunctionBody -match 'IdentityToken' -and $stopFunctionBody -match 'LifecycleLock' -and $stopFunctionBody -match 'Assert-ThriveLensLifecycleLockOwnership' -and $stopFunctionBody -match 'Invoke-ThriveLensGuardedDistro') 'GRACEFUL_STOP_IDENTITY_FENCED'
 A ($stopFunctionBody -match 'Assert-ThriveLensWslAbsent' -and $stopFunctionBody -notmatch 'Assert-ThriveLensHostPortAbsent') 'GRACEFUL_STOP_GUEST_ABSENCE_ONLY'
 A ($terminateBody.IndexOf('Assert-ThriveLensDistroStopped') -ge 0 -and $terminateBody.IndexOf('Assert-ThriveLensHostPortAbsent') -gt $terminateBody.IndexOf('Assert-ThriveLensDistroStopped')) 'TERMINATE_FINAL_HOST_ABSENCE_ORDERED'
 $runtimeTest=Get-Content (Join-Path $PSScriptRoot 'test_runtime.ps1') -Raw
 $runtimeTokens=$null;$runtimeParseErrors=$null;$runtimeAst=[Management.Automation.Language.Parser]::ParseInput($runtimeTest,[ref]$runtimeTokens,[ref]$runtimeParseErrors)
 $pseudoFinallyCommands=@($runtimeAst.FindAll({param($node)$node -is [Management.Automation.Language.CommandAst] -and $node.GetCommandName() -ceq 'finally'},$true))
 A ($runtimeParseErrors.Count -eq 0 -and $pseudoFinallyCommands.Count -eq 0) 'RUNTIME_FINALLY_AST_BOUND'
 $policyFunctions=@($runtimeAst.FindAll({param($node)$node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq 'Get-ThriveLensInterCycleMemoryTargetBytes'},$true));$policyDefinition=if($policyFunctions.Count -eq 1){$policyFunctions[0].Extent.Text}else{''}
 A (Test-ThriveLensInterCyclePolicyContract -Source $runtimeTest) 'INTER_CYCLE_POLICY_EXACT_MAX_CONTRACT'
 $policyInstallMax=Invoke-ThriveLensInterCyclePolicyHarness $policyDefinition ([int64]1024) ([int64]2048);A ($null -eq $policyInstallMax.Code -and $policyInstallMax.Value -is [int64] -and $policyInstallMax.Value -eq 2048) 'INTER_CYCLE_POLICY_INSTALL_MAX'
 $policyRuntimeMax=Invoke-ThriveLensInterCyclePolicyHarness $policyDefinition ([int64]4096) ([int64]2048);A ($null -eq $policyRuntimeMax.Code -and $policyRuntimeMax.Value -eq 4096) 'INTER_CYCLE_POLICY_RUNTIME_MAX'
 foreach($invalidPolicyCase in @(@($true,[int64]2048),@($null,[int64]2048),@('-1',[int64]2048),@([double]2048,[int64]2048),@([decimal]2048,[int64]2048),@([int64]0,[int64]2048),@([int64]-1,[int64]2048))){$invalidPolicy=Invoke-ThriveLensInterCyclePolicyHarness $policyDefinition $invalidPolicyCase[0] $invalidPolicyCase[1];A ($invalidPolicy.Code -ceq 'RUNTIME_MEMORY_POLICY_INVALID' -and $null -eq $invalidPolicy.Value) 'INTER_CYCLE_POLICY_INVALID_SOURCE_FAILS_CLOSED'}
 $multiplePolicy=Invoke-ThriveLensInterCyclePolicyHarness -Definition $policyDefinition -RuntimeValue ([object[]]@([int64]1024,[int64]2048)) -InstallValue ([int64]2048);A ($multiplePolicy.Code -ceq 'RUNTIME_MEMORY_POLICY_INVALID' -and $null -eq $multiplePolicy.Value) 'INTER_CYCLE_POLICY_MULTIPLE_SOURCE_FAILS_CLOSED'
 $runtimeImportFailure=Invoke-ThriveLensRuntimeImportFailureHarness -Source $runtimeTest
 A ($null -ne $runtimeImportFailure -and $runtimeImportFailure.schema_version -eq 2 -and $runtimeImportFailure.status -ceq 'ERROR' -and $runtimeImportFailure.code -ceq 'RUNTIME_TEST_INTERNAL_ERROR' -and $runtimeImportFailure.original_code -ceq 'RUNTIME_TEST_INTERNAL_ERROR' -and -not $runtimeImportFailure.cleanup_required -and -not $runtimeImportFailure.cleanup_verified -and -not $runtimeImportFailure.guest_cleanup_attempted -and -not $runtimeImportFailure.forced_termination_attempted -and -not $runtimeImportFailure.post_mutation_resource_gate_verified -and -not $runtimeImportFailure.configuration_lease_release_attempted -and -not $runtimeImportFailure.lifecycle_lock_release_attempted -and ($runtimeImportFailure|ConvertTo-Json -Compress) -notmatch 'synthetic|private|import failure') 'RUNTIME_IMPORT_FAILURE_CLOSED_WITHOUT_MODULE_CALLS_OR_RAW_TEXT'
 $runtimeInitialDrain=Invoke-ThriveLensRuntimeInitialDrainHarness -Source $runtimeTest
 A ($null -ne $runtimeInitialDrain -and $runtimeInitialDrain.schema_version -eq 2 -and $runtimeInitialDrain.status -ceq 'ERROR' -and $runtimeInitialDrain.code -ceq 'RESOURCE_GATE_OUTPUT_DRAIN_INCOMPLETE' -and $runtimeInitialDrain.original_code -ceq 'RESOURCE_GATE_OUTPUT_DRAIN_INCOMPLETE' -and -not $runtimeInitialDrain.cleanup_required -and -not $runtimeInitialDrain.cleanup_verified -and -not $runtimeInitialDrain.guest_cleanup_allowed -and -not $runtimeInitialDrain.guest_cleanup_attempted -and -not $runtimeInitialDrain.forced_termination_attempted -and -not $runtimeInitialDrain.post_mutation_resource_gate_verified -and -not $runtimeInitialDrain.configuration_lease_release_attempted -and -not $runtimeInitialDrain.lifecycle_lock_release_attempted) 'RUNTIME_INITIAL_RESOURCE_GATE_OUTPUT_DRAIN_FATAL_NO_MUTATION_OR_RETRY'
 $clusterIdentityFunctions=@($runtimeAst.FindAll({param($node)$node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq 'Get-ThriveLensPrivateClusterIdentityFingerprint'},$true));$clusterIdentityDefinition=if($clusterIdentityFunctions.Count -eq 1){$clusterIdentityFunctions[0].Extent.Text}else{''}
 $identitySuccess=Invoke-ThriveLensClusterIdentityHarness -Definition $clusterIdentityDefinition -Mode 'SUCCESS';$syntheticIdentityBytes=[Text.Encoding]::ASCII.GetBytes('7234567890123456789');try{$expectedIdentityFingerprint=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($syntheticIdentityBytes))}finally{[Array]::Clear($syntheticIdentityBytes,0,$syntheticIdentityBytes.Length)}
 A ($null -eq $identitySuccess.Code -and $identitySuccess.Bound -and $identitySuccess.Value -ceq $expectedIdentityFingerprint -and $identitySuccess.Value -cnotmatch '7234567890123456789' -and ($identitySuccess.Log -join ',') -ceq 'IDENTITY,PG_CONTROLDATA') 'RUNTIME_CLUSTER_IDENTITY_PRIVATE_HASH_ONLY'
 foreach($identityFailureCase in @(@('EXIT','POSTGRES_SYSTEM_IDENTIFIER_PROBE_FAILED'),@('STDERR','POSTGRES_SYSTEM_IDENTIFIER_PROBE_FAILED'),@('DUPLICATE','POSTGRES_SYSTEM_IDENTIFIER_INVALID'),@('ZERO','POSTGRES_SYSTEM_IDENTIFIER_INVALID'),@('OVERFLOW','POSTGRES_SYSTEM_IDENTIFIER_INVALID'),@('MALFORMED','POSTGRES_SYSTEM_IDENTIFIER_INVALID'))){$identityFailure=Invoke-ThriveLensClusterIdentityHarness -Definition $clusterIdentityDefinition -Mode $identityFailureCase[0];A ($identityFailure.Code -ceq $identityFailureCase[1] -and $null -eq $identityFailure.Value -and $identityFailure.Bound) ('RUNTIME_CLUSTER_IDENTITY_'+$identityFailureCase[0]+'_FAILS_CLOSED')}
 $wslParsed=Get-ThriveLensParsedSource -Source $module;$startCoreAst=Get-ThriveLensFunctionAst -Ast $wslParsed.Ast -Name 'Invoke-ThriveLensPostgresStartUnderLock';$startCoreDefinition=if($null -ne $startCoreAst){$startCoreAst.Extent.Text}else{''}
 A (Test-ThriveLensStartCoreContract -Source $module) 'START_CORE_EXACT_TRANSACTION_CONTRACT'
 $coreSuccess=Invoke-ThriveLensStartCoreHarness -Definition $startCoreDefinition -Mode 'SUCCESS'
 $expectedCoreLog='LOCK,LEASE_ASSERT,FINGERPRINT,LEASE_CONTRACT,LEASE_RESOURCE,PATHS,RESOURCE,MEMORY_POLICY,RAM,WSL_IDENTITY,PACKAGES,DISK,CLUSTER,WSL_ABSENT,HOST_ABSENT,TERMINATE,SETTLE:2048,LEASE_ASSERT,FINGERPRINT,WSL_IDENTITY,WSL_ABSENT,HOST_ABSENT,RAM,PG_CTL,WSL_LOOPBACK,HOST_LOOPBACK,RESOURCE'
 A ($null -eq $coreSuccess.Code -and $coreSuccess.WslTouched -and $coreSuccess.StartAttempted -and $coreSuccess.StartCommitResourceGateVerified -and ($coreSuccess.Log -join ',') -ceq $expectedCoreLog) 'START_CORE_EXECUTABLE_EXACT_ORDER'
 $coreEarly=Invoke-ThriveLensStartCoreHarness -Definition $startCoreDefinition -Mode 'EARLY_RESOURCE';A ($coreEarly.Code -ceq 'RESOURCE_GATE_FAILED' -and -not $coreEarly.WslTouched -and -not $coreEarly.StartAttempted -and -not $coreEarly.StartCommitResourceGateVerified -and ($coreEarly.Log -join ',') -ceq 'LOCK,LEASE_ASSERT,FINGERPRINT,LEASE_CONTRACT,LEASE_RESOURCE,PATHS,RESOURCE') 'START_CORE_EXECUTABLE_EARLY_FAILURE_FLAGS'
 $coreInitialMeasurementMutation=$module.Replace("throw 'MEMORY_MEASUREMENT_UNAVAILABLE'","throw 'LOW_FREE_MEMORY_AFTER_LIFECYCLE_LOCK'")
 $coreInitialMeasurementMutationKilled=([regex]::Matches($module,[regex]::Escape("throw 'MEMORY_MEASUREMENT_UNAVAILABLE'")).Count -eq 3 -and [regex]::Matches($coreInitialMeasurementMutation,[regex]::Escape("throw 'MEMORY_MEASUREMENT_UNAVAILABLE'")).Count -eq 0 -and (Test-ThriveLensSourceParses -Source $coreInitialMeasurementMutation) -and -not (Test-ThriveLensStartCoreContract -Source $coreInitialMeasurementMutation))
 $coreRam1=Invoke-ThriveLensStartCoreHarness -Definition $startCoreDefinition -Mode 'RAM1_LOW';A ($coreRam1.Code -ceq 'LOW_FREE_MEMORY_AFTER_LIFECYCLE_LOCK' -and -not $coreRam1.WslTouched -and -not $coreRam1.StartAttempted -and ($coreRam1.Log -join ',') -match 'MEMORY_POLICY,RAM$' -and $coreInitialMeasurementMutationKilled) 'START_CORE_INITIAL_RUNTIME_FLOOR_UNCHANGED'
 $coreRam1Invalid=Invoke-ThriveLensStartCoreHarness -Definition $startCoreDefinition -Mode 'RAM1_INVALID';A ($coreRam1Invalid.Code -ceq 'MEMORY_MEASUREMENT_UNAVAILABLE' -and -not $coreRam1Invalid.WslTouched -and -not $coreRam1Invalid.StartAttempted -and -not $coreRam1Invalid.StartCommitResourceGateVerified -and ($coreRam1Invalid.Log -join ',') -match 'MEMORY_POLICY,RAM$') 'START_CORE_INITIAL_RAM_INVALID_FAILS_CLOSED_ZERO_WSL'
 $coreMid=Invoke-ThriveLensStartCoreHarness -Definition $startCoreDefinition -Mode 'MID_PACKAGES';A ($coreMid.Code -ceq 'WSL_PACKAGE_MISMATCH' -and $coreMid.WslTouched -and -not $coreMid.StartAttempted -and ($coreMid.Log -join ',') -match 'WSL_IDENTITY,PACKAGES$') 'START_CORE_EXECUTABLE_MID_FAILURE_FLAGS'
 $coreSettleLow=Invoke-ThriveLensStartCoreHarness -Definition $startCoreDefinition -Mode 'SETTLE_LOW';A ($coreSettleLow.Code -ceq 'LOW_FREE_MEMORY_AFTER_WSL_PROBES' -and $coreSettleLow.WslTouched -and -not $coreSettleLow.StartAttempted -and ($coreSettleLow.Log -join ',') -match 'TERMINATE,SETTLE:2048$') 'START_CORE_SETTLE_TIMEOUT_MAPS_LOW_MEMORY_ZERO_PGCTL'
 $coreSettleMeasurement=Invoke-ThriveLensStartCoreHarness -Definition $startCoreDefinition -Mode 'SETTLE_MEASUREMENT';A ($coreSettleMeasurement.Code -ceq 'MEMORY_MEASUREMENT_UNAVAILABLE_AFTER_WSL_PROBES' -and $coreSettleMeasurement.WslTouched -and -not $coreSettleMeasurement.StartAttempted -and ($coreSettleMeasurement.Log -join ',') -match 'TERMINATE,SETTLE:2048$') 'START_CORE_SETTLE_MEASUREMENT_MAPS_ZERO_PGCTL'
 $coreSettleUnknown=Invoke-ThriveLensStartCoreHarness -Definition $startCoreDefinition -Mode 'SETTLE_UNKNOWN';A ($coreSettleUnknown.Code -ceq 'MEMORY_MEASUREMENT_UNAVAILABLE_AFTER_WSL_PROBES' -and -not $coreSettleUnknown.StartAttempted) 'START_CORE_SETTLE_UNKNOWN_SANITIZED_ZERO_PGCTL'
 $coreRam2=Invoke-ThriveLensStartCoreHarness -Definition $startCoreDefinition -Mode 'RAM2_LOW';A ($coreRam2.Code -ceq 'LOW_FREE_MEMORY_AFTER_WSL_PROBES' -and $coreRam2.WslTouched -and -not $coreRam2.StartAttempted -and ($coreRam2.Log -join ',') -match 'WSL_IDENTITY,WSL_ABSENT,HOST_ABSENT,RAM$') 'START_CORE_EXECUTABLE_SECOND_RAM_FENCE'
 $coreRam2Invalid=Invoke-ThriveLensStartCoreHarness -Definition $startCoreDefinition -Mode 'RAM2_INVALID';A ($coreRam2Invalid.Code -ceq 'MEMORY_MEASUREMENT_UNAVAILABLE_AFTER_WSL_PROBES' -and -not $coreRam2Invalid.StartAttempted -and ($coreRam2Invalid.Log -join ',') -match 'HOST_ABSENT,RAM$') 'START_CORE_FINAL_RAM_INVALID_ZERO_PGCTL'
 $coreLeaseFence=Invoke-ThriveLensStartCoreHarness -Definition $startCoreDefinition -Mode 'COMMIT_LEASE_FAIL';A ($coreLeaseFence.Code -ceq 'CONFIGURATION_LEASE_CONTENT_CHANGED' -and $coreLeaseFence.WslTouched -and -not $coreLeaseFence.StartAttempted -and ($coreLeaseFence.Log -join ',') -match 'SETTLE:2048,LEASE_ASSERT$') 'START_CORE_EXECUTABLE_COMMIT_LEASE_FENCE'
 $coreStartFail=Invoke-ThriveLensStartCoreHarness -Definition $startCoreDefinition -Mode 'START_FAIL';A ($coreStartFail.Code -ceq 'POSTGRES_START_FAILED' -and $coreStartFail.WslTouched -and $coreStartFail.StartAttempted -and ($coreStartFail.Log -join ',') -match 'WSL_IDENTITY,WSL_ABSENT,HOST_ABSENT,RAM,PG_CTL$') 'START_CORE_EXECUTABLE_ATTEMPTED_ADJACENCY'
 $corePost=Invoke-ThriveLensStartCoreHarness -Definition $startCoreDefinition -Mode 'POST_GATE';A ($corePost.Code -ceq 'POST_MUTATION_RESOURCE_GATE_FAILED' -and $corePost.WslTouched -and $corePost.StartAttempted -and -not $corePost.StartCommitResourceGateVerified -and ($corePost.Log -join ',') -match 'PG_CTL,WSL_LOOPBACK,HOST_LOOPBACK,RESOURCE$') 'START_CORE_EXECUTABLE_POST_START_FAILURE'

 $adapterSuccess=Invoke-ThriveLensStartAdapterHarness -Source $startRaw -Mode 'SUCCESS';A ($null -ne $adapterSuccess.Adapter -and $adapterSuccess.Adapter.ExitCode -eq 0 -and $adapterSuccess.Adapter.Response.status -ceq 'STARTED' -and $adapterSuccess.Adapter.Response.port -eq 55439 -and $adapterSuccess.TokenCalls -eq 1 -and $adapterSuccess.SameToken -and $adapterSuccess.SameConfiguration -and ($adapterSuccess.Log -join ',') -ceq 'LOCK_ENTER,LEASE_ENTER,LEASE_ASSERT,CONTRACT,PATHS,TOKEN,CORE,LEASE_ASSERT,LEASE_RELEASE,LEASE_RELEASED,LOCK_RELEASE,LOCK_RELEASED') 'START_ADAPTER_EXECUTABLE_SUCCESS_REVERSE_DISPOSE_ORDER'
 $startImportFailure=Invoke-ThriveLensStartImportFailureHarness -Source $startRaw;A ($null -ne $startImportFailure -and $startImportFailure.ExitCode -eq 3 -and $startImportFailure.Response.schema_version -eq 1 -and $startImportFailure.Response.status -ceq 'ERROR' -and $startImportFailure.Response.code -ceq 'POSTGRES_START_CLEANUP_FAILED' -and $startImportFailure.Response.original_code -ceq 'POSTGRES_START_INTERNAL_ERROR' -and -not $startImportFailure.Response.cleanup_required -and -not $startImportFailure.Response.cleanup_verified -and -not $startImportFailure.Response.guest_cleanup_attempted -and -not $startImportFailure.Response.forced_termination_attempted -and -not $startImportFailure.Response.configuration_lease_release_attempted -and -not $startImportFailure.Response.lifecycle_lock_release_attempted -and ($startImportFailure|ConvertTo-Json -Compress) -notmatch 'synthetic|private|import failure') 'START_IMPORT_FAILURE_CLOSED_WITHOUT_MODULE_CALLS_OR_RAW_TEXT'
 $adapterPreLease=Invoke-ThriveLensStartAdapterHarness -Source $startRaw -Mode 'PRE_LEASE_FAIL';A ($adapterPreLease.Adapter.ExitCode -eq 3 -and $adapterPreLease.Adapter.Response.status -ceq 'ERROR' -and $adapterPreLease.Adapter.Response.code -ceq 'POSTGRES_START_CLEANUP_FAILED' -and $adapterPreLease.Adapter.Response.original_code -ceq 'CONFIGURATION_LEASE_OPEN_FAILED' -and -not $adapterPreLease.Adapter.Response.cleanup_required -and -not $adapterPreLease.Adapter.Response.cleanup_verified -and -not $adapterPreLease.Adapter.Response.post_mutation_resource_gate_verified -and $adapterPreLease.TokenCalls -eq 0 -and $adapterPreLease.SameToken -and $adapterPreLease.SameConfiguration -and @($adapterPreLease.Log) -notcontains 'CONTRACT' -and @($adapterPreLease.Log) -notcontains 'PATHS' -and @($adapterPreLease.Log) -notcontains 'DISTRO_ABSENT' -and @($adapterPreLease.Log) -notcontains 'HOST_ABSENT' -and @($adapterPreLease.Log) -notcontains 'FINAL_GATE' -and ($adapterPreLease.Log -join ',') -ceq 'LOCK_ENTER,LEASE_ENTER,GUEST_POLICY,LOCK_RELEASE,LOCK_RELEASED') 'START_ADAPTER_EXECUTABLE_PRE_LEASE_FAILURE_NO_CONFIGURATION_REREAD_OR_ABSENCE'
 $adapterEarly=Invoke-ThriveLensStartAdapterHarness -Source $startRaw -Mode 'EARLY_FAIL';A ($adapterEarly.Adapter.ExitCode -eq 2 -and $adapterEarly.Adapter.Response.status -ceq 'BLOCKED' -and $adapterEarly.Adapter.Response.code -ceq 'RESOURCE_GATE_FAILED' -and -not $adapterEarly.Adapter.Response.cleanup_required -and $adapterEarly.Adapter.Response.cleanup_verified -and -not $adapterEarly.Adapter.Response.guest_cleanup_attempted -and -not $adapterEarly.Adapter.Response.forced_termination_attempted -and $adapterEarly.TokenCalls -eq 1 -and $adapterEarly.SameToken -and $adapterEarly.SameConfiguration -and @($adapterEarly.Log) -notcontains 'STOP' -and @($adapterEarly.Log) -notcontains 'FORCE' -and ($adapterEarly.Log -join ',') -match 'LEASE_RELEASE,LEASE_RELEASED,LOCK_RELEASE,LOCK_RELEASED$') 'START_ADAPTER_EXECUTABLE_EARLY_FAILURE'
 $adapterMid=Invoke-ThriveLensStartAdapterHarness -Source $startRaw -Mode 'MID_FAIL';A ($adapterMid.Adapter.ExitCode -eq 2 -and $adapterMid.Adapter.Response.status -ceq 'BLOCKED' -and $adapterMid.Adapter.Response.code -ceq 'WSL_PACKAGE_MISMATCH' -and $adapterMid.Adapter.Response.cleanup_required -and $adapterMid.Adapter.Response.cleanup_verified -and -not $adapterMid.Adapter.Response.guest_cleanup_attempted -and $adapterMid.Adapter.Response.forced_termination_attempted -and $adapterMid.TokenCalls -eq 1 -and $adapterMid.SameToken -and $adapterMid.SameConfiguration -and @($adapterMid.Log) -contains 'FORCE' -and @($adapterMid.Log) -notcontains 'STOP') 'START_ADAPTER_EXECUTABLE_MID_SAME_TOKEN_CONTAINMENT'
 foreach($postProbeCase in @([pscustomobject]@{Mode='POST_PROBE_LOW';Code='LOW_FREE_MEMORY_AFTER_WSL_PROBES'},[pscustomobject]@{Mode='POST_PROBE_MEASUREMENT';Code='MEMORY_MEASUREMENT_UNAVAILABLE_AFTER_WSL_PROBES'})){$postProbeAdapter=Invoke-ThriveLensStartAdapterHarness -Source $startRaw -Mode $postProbeCase.Mode;A ($postProbeAdapter.Adapter.ExitCode -eq 2 -and $postProbeAdapter.Adapter.Response.status -ceq 'BLOCKED' -and $postProbeAdapter.Adapter.Response.code -ceq $postProbeCase.Code -and $postProbeAdapter.Adapter.Response.original_code -ceq $postProbeCase.Code -and $postProbeAdapter.Adapter.Response.cleanup_required -and $postProbeAdapter.Adapter.Response.cleanup_verified -and -not $postProbeAdapter.Adapter.Response.guest_cleanup_attempted -and $postProbeAdapter.Adapter.Response.forced_termination_attempted -and @($postProbeAdapter.Log) -notcontains 'STOP' -and ($postProbeAdapter.Log -join ',') -match 'FORCE,DISTRO_ABSENT,HOST_ABSENT,LEASE_RELEASE,LEASE_RELEASED,LOCK_RELEASE,LOCK_RELEASED$') ('START_ADAPTER_'+$postProbeCase.Code+'_ALREADY_STOPPED_CONTAINMENT')}
 $adapterPost=Invoke-ThriveLensStartAdapterHarness -Source $startRaw -Mode 'POST_FAIL';A ($adapterPost.Adapter.ExitCode -eq 3 -and $adapterPost.Adapter.Response.status -ceq 'ERROR' -and $adapterPost.Adapter.Response.code -ceq 'POST_MUTATION_RESOURCE_GATE_FAILED' -and $adapterPost.Adapter.Response.guest_cleanup_attempted -and $adapterPost.Adapter.Response.forced_termination_attempted -and $adapterPost.TokenCalls -eq 1 -and $adapterPost.SameToken -and $adapterPost.SameConfiguration -and ($adapterPost.Log -join ',') -match 'IDENTITY,STOP,IDENTITY,FORCE') 'START_ADAPTER_EXECUTABLE_POST_START_CONTAINMENT'
 $adapterDrain=Invoke-ThriveLensStartAdapterHarness -Source $startRaw -Mode 'OUTPUT_DRAIN';A ($adapterDrain.Adapter.ExitCode -eq 3 -and $adapterDrain.Adapter.Response.status -ceq 'ERROR' -and $adapterDrain.Adapter.Response.code -ceq 'POST_MUTATION_RESOURCE_GATE_FAILED' -and $adapterDrain.Adapter.Response.original_code -ceq 'RESOURCE_GATE_OUTPUT_DRAIN_INCOMPLETE' -and $adapterDrain.Adapter.Response.cleanup_required -and -not $adapterDrain.Adapter.Response.cleanup_verified -and -not $adapterDrain.Adapter.Response.guest_cleanup_allowed -and -not $adapterDrain.Adapter.Response.guest_cleanup_attempted -and $adapterDrain.Adapter.Response.forced_termination_attempted -and -not $adapterDrain.Adapter.Response.post_mutation_resource_gate_verified -and $adapterDrain.SameToken -and $adapterDrain.SameConfiguration -and @($adapterDrain.Log) -notcontains 'STOP' -and @($adapterDrain.Log) -notcontains 'FINAL_GATE' -and ($adapterDrain.Log -join ',') -match 'GUEST_POLICY,IDENTITY,IDENTITY,FORCE,DISTRO_ABSENT,HOST_ABSENT,LEASE_RELEASE,LEASE_RELEASED,LOCK_RELEASE,LOCK_RELEASED$') 'START_ADAPTER_OUTPUT_DRAIN_CONTAINMENT_WITHOUT_GUEST_OR_RERUN'
 $initialResourceCodes=@('RESOURCE_GATE_UNAVAILABLE','RESOURCE_GATE_FAILED','RESOURCE_GATE_RESULT_INVALID','RESOURCE_GATE_MANIFEST_INVALID','RESOURCE_GATE_PROCESS_START_FAILED','RESOURCE_GATE_TIMEOUT','RESOURCE_GATE_OUTPUT_LIMIT','WSL_STANDARD_INPUT_INVALID','WSL_STANDARD_INPUT_LIMIT_EXCEEDED')
 foreach($initialResourceCode in $initialResourceCodes){
  $startResourceFailure=Invoke-ThriveLensStartAdapterHarness -Source $startRaw -Mode $initialResourceCode
  A ($startResourceFailure.Adapter.ExitCode -eq 2 -and $startResourceFailure.Adapter.Response.status -ceq 'BLOCKED' -and $startResourceFailure.Adapter.Response.code -ceq $initialResourceCode -and $startResourceFailure.Adapter.Response.original_code -ceq $initialResourceCode -and -not $startResourceFailure.Adapter.Response.cleanup_required -and $startResourceFailure.Adapter.Response.cleanup_verified -and -not $startResourceFailure.Adapter.Response.guest_cleanup_attempted -and -not $startResourceFailure.Adapter.Response.forced_termination_attempted -and -not $startResourceFailure.Adapter.Response.post_mutation_resource_gate_verified -and @($startResourceFailure.Log) -notcontains 'STOP' -and @($startResourceFailure.Log) -notcontains 'FORCE' -and @($startResourceFailure.Log) -notcontains 'FINAL_GATE') ('START_INITIAL_'+$initialResourceCode+'_BLOCKED_PARITY')
  $runtimeResourceFailure=Resolve-ThriveLensRuntimeCleanupOutcome -OriginalCode $initialResourceCode -OriginalExitCode 2 -CleanupRequired $false -CleanupAuthorityVerified $true -CredentialCleanupRequired $false -CredentialRemoveFailed $false -CredentialAbsenceVerified $true -IdentityChanged $false -PostgresStopFailed $false -DistroTerminateFailed $false -DistroAbsenceCheckFailed $false -HostAbsenceCheckFailed $false -DistroAbsent $true -HostAbsent $true -LockReleaseFailed $false
  A ($runtimeResourceFailure.ExitCode -eq 2 -and $runtimeResourceFailure.Status -ceq 'BLOCKED' -and $runtimeResourceFailure.Code -ceq $initialResourceCode -and $runtimeResourceFailure.OriginalCode -ceq $initialResourceCode -and $runtimeResourceFailure.CleanupVerified) ('RUNTIME_INITIAL_'+$initialResourceCode+'_BLOCKED_PARITY')
 }
 $initialDrain=Invoke-ThriveLensStartAdapterHarness -Source $startRaw -Mode 'INITIAL_OUTPUT_DRAIN';A ($initialDrain.Adapter.ExitCode -eq 3 -and $initialDrain.Adapter.Response.status -ceq 'ERROR' -and $initialDrain.Adapter.Response.code -ceq 'RESOURCE_GATE_OUTPUT_DRAIN_INCOMPLETE' -and $initialDrain.Adapter.Response.original_code -ceq 'RESOURCE_GATE_OUTPUT_DRAIN_INCOMPLETE' -and -not $initialDrain.Adapter.Response.cleanup_required -and -not $initialDrain.Adapter.Response.cleanup_verified -and -not $initialDrain.Adapter.Response.guest_cleanup_allowed -and -not $initialDrain.Adapter.Response.guest_cleanup_attempted -and -not $initialDrain.Adapter.Response.forced_termination_attempted -and -not $initialDrain.Adapter.Response.post_mutation_resource_gate_verified -and @($initialDrain.Log) -notcontains 'STOP' -and @($initialDrain.Log) -notcontains 'FORCE' -and @($initialDrain.Log) -notcontains 'FINAL_GATE') 'START_INITIAL_RESOURCE_GATE_OUTPUT_DRAIN_FATAL_NO_MUTATION_OR_RETRY'
 $adapterFinalGate=Invoke-ThriveLensStartAdapterHarness -Source $startRaw -Mode 'FINAL_GATE_FAIL';A ($adapterFinalGate.Adapter.ExitCode -eq 3 -and $adapterFinalGate.Adapter.Response.code -ceq 'POST_MUTATION_RESOURCE_GATE_FAILED' -and -not $adapterFinalGate.Adapter.Response.post_mutation_resource_gate_verified -and $adapterFinalGate.Adapter.Response.guest_cleanup_attempted -and $adapterFinalGate.Adapter.Response.forced_termination_attempted -and $adapterFinalGate.SameToken -and $adapterFinalGate.SameConfiguration -and ($adapterFinalGate.Log -join ',') -match 'STOP,IDENTITY,FORCE,DISTRO_ABSENT,HOST_ABSENT,FINAL_GATE,LEASE_RELEASE,LEASE_RELEASED,LOCK_RELEASE,LOCK_RELEASED$') 'START_ADAPTER_FINAL_GATE_FAILURE_AFTER_CONTAINMENT'
 $adapterStopFail=Invoke-ThriveLensStartAdapterHarness -Source $startRaw -Mode 'STOP_FAIL';A ($adapterStopFail.Adapter.ExitCode -eq 3 -and $adapterStopFail.Adapter.Response.code -ceq 'POSTGRES_START_CLEANUP_FAILED' -and $adapterStopFail.Adapter.Response.guest_cleanup_attempted -and $adapterStopFail.Adapter.Response.forced_termination_attempted -and $adapterStopFail.TokenCalls -eq 1 -and $adapterStopFail.SameToken -and $adapterStopFail.SameConfiguration -and ($adapterStopFail.Log -join ',') -match 'STOP,IDENTITY,FORCE') 'START_ADAPTER_EXECUTABLE_FORCED_AFTER_STOP_FAILURE'
 $adapterLockRelease=Invoke-ThriveLensStartAdapterHarness -Source $startRaw -Mode 'LOCK_RELEASE_FAIL';A ($adapterLockRelease.Adapter.ExitCode -eq 3 -and $adapterLockRelease.Adapter.Response.status -ceq 'ERROR' -and $adapterLockRelease.Adapter.Response.code -ceq 'POST_MUTATION_RESOURCE_GATE_FAILED' -and $adapterLockRelease.Adapter.Response.original_code -ceq 'POSTGRES_START_LOCK_RELEASE_FAILED' -and -not $adapterLockRelease.Adapter.Response.guest_cleanup_attempted -and $adapterLockRelease.Adapter.Response.forced_termination_attempted -and -not $adapterLockRelease.Adapter.Response.post_mutation_resource_gate_verified -and $adapterLockRelease.Adapter.Response.configuration_lease_released -and $adapterLockRelease.Adapter.Response.lifecycle_lock_release_attempted -and -not $adapterLockRelease.Adapter.Response.lifecycle_lock_released -and $adapterLockRelease.TokenCalls -eq 1 -and $adapterLockRelease.SameToken -and $adapterLockRelease.SameConfiguration -and ($adapterLockRelease.Log -join ',') -match 'LEASE_RELEASED,LOCK_RELEASE,GUEST_POLICY,IDENTITY,IDENTITY,FORCE,DISTRO_ABSENT,HOST_ABSENT$') 'START_ADAPTER_EXECUTABLE_LOCK_RELEASE_FAILURE_TRUTH'
 $adapterLeaseRelease=Invoke-ThriveLensStartAdapterHarness -Source $startRaw -Mode 'LEASE_RELEASE_FAIL';A ($adapterLeaseRelease.Adapter.ExitCode -eq 3 -and $adapterLeaseRelease.Adapter.Response.status -ceq 'ERROR' -and $adapterLeaseRelease.Adapter.Response.code -ceq 'POST_MUTATION_RESOURCE_GATE_FAILED' -and $adapterLeaseRelease.Adapter.Response.original_code -ceq 'POSTGRES_START_CONFIGURATION_LEASE_RELEASE_FAILED' -and -not $adapterLeaseRelease.Adapter.Response.guest_cleanup_attempted -and $adapterLeaseRelease.Adapter.Response.forced_termination_attempted -and -not $adapterLeaseRelease.Adapter.Response.post_mutation_resource_gate_verified -and $adapterLeaseRelease.Adapter.Response.configuration_lease_release_attempted -and -not $adapterLeaseRelease.Adapter.Response.configuration_lease_released -and $adapterLeaseRelease.Adapter.Response.lifecycle_lock_released -and $adapterLeaseRelease.TokenCalls -eq 1 -and $adapterLeaseRelease.SameToken -and $adapterLeaseRelease.SameConfiguration -and (@($adapterLeaseRelease.Log|Where-Object{$_ -ceq 'LEASE_RELEASE'}).Count -eq 1) -and ($adapterLeaseRelease.Log -join ',') -match 'LEASE_RELEASE,GUEST_POLICY,IDENTITY,IDENTITY,FORCE,DISTRO_ABSENT,HOST_ABSENT,LOCK_RELEASE,LOCK_RELEASED$') 'START_ADAPTER_EXECUTABLE_LEASE_RELEASE_FAILURE_TRUTH'
 $credentialFunctionStart=$runtimeTest.IndexOf('function Remove-ThriveLensRuntimeCredential');$credentialFunctionEnd=$runtimeTest.IndexOf('function Assert-ThriveLensAuthenticatedScalar',$credentialFunctionStart);$credentialFunctionBody=if($credentialFunctionStart -ge 0 -and $credentialFunctionEnd -gt $credentialFunctionStart){$runtimeTest.Substring($credentialFunctionStart,$credentialFunctionEnd-$credentialFunctionStart)}else{''}
 $removeCatchIndex=$credentialFunctionBody.IndexOf('$removeRawCode=');$absenceProbeIndex=$credentialFunctionBody.IndexOf("Invoke-ThriveLensGuardedDistro -IdentityToken `$IdentityToken -LifecycleLock `$LifecycleLock -Contract `$Contract -Arguments @('/usr/bin/test'",$removeCatchIndex);$credentialResolverIndex=if($absenceProbeIndex -ge 0){$credentialFunctionBody.IndexOf('Resolve-ThriveLensCredentialCleanupResult',$absenceProbeIndex)}else{-1}
 A ($removeCatchIndex -ge 0 -and $absenceProbeIndex -gt $removeCatchIndex -and $credentialResolverIndex -gt $absenceProbeIndex -and $credentialFunctionBody -match 'Test-ThriveLensCredentialAbsenceProbeAllowed') 'CREDENTIAL_REMOVE_FAILURE_THEN_BOUNDED_ABSENCE_FLOW'
 $credentialTestModule=New-Module -ArgumentList $credentialFunctionBody -ScriptBlock {
  param([string]$Definition)
  $script:Scenario='SUCCESS';$script:IdentityAssertCalls=0;$script:GuardedCalls=0;$script:ConfigurationPreserved=$true;$script:CallLog=[Collections.Generic.List[string]]::new();$script:ExpectedContract=$null
  function Assert-ThriveLensWslCleanupIdentity {
   param($IdentityToken,$LifecycleLock,$Contract)
   $script:IdentityAssertCalls++
   if(-not [object]::ReferenceEquals($Contract,$script:ExpectedContract)){$script:ConfigurationPreserved=$false;throw 'SYNTHETIC_CONFIGURATION_CHANGED'}
   $assertFailures=@{ASSERT_IDENTITY='WSL_CLEANUP_IDENTITY_CHANGED';ASSERT_LOCK='LIFECYCLE_LOCK_OWNERSHIP_REQUIRED';ASSERT_CONTAINMENT='WSL_GUARDED_COMMAND_CONTAINMENT_FAILED';ASSERT_UNKNOWN='untrusted raw failure'}
   if($assertFailures.ContainsKey($script:Scenario)){throw $assertFailures[$script:Scenario]}
   return $true
  }
  function Invoke-ThriveLensGuardedDistro {
   param($IdentityToken,$LifecycleLock,$Contract,[string[]]$Arguments)
   if(-not [object]::ReferenceEquals($Contract,$script:ExpectedContract)){$script:ConfigurationPreserved=$false;throw 'SYNTHETIC_CONFIGURATION_CHANGED'}
   $script:GuardedCalls++;$script:CallLog.Add(($Arguments[0]+'|'+$Arguments[-1]))
   if($Arguments[0] -ceq '/usr/bin/rm'){
    $removeFailures=@{
     REMOVE_TIMEOUT='WSL_COMMAND_TIMEOUT';REMOVE_OUTPUT_LIMIT='WSL_OUTPUT_LIMIT_EXCEEDED';REMOVE_DRAIN='WSL_OUTPUT_DRAIN_INCOMPLETE';REMOVE_START='WSL_PROCESS_START_FAILED';
     REMOVE_TIMEOUT_ABSENCE_FALSE='WSL_COMMAND_TIMEOUT';REMOVE_TIMEOUT_ABSENCE_THROW='WSL_COMMAND_TIMEOUT';
     REMOVE_IDENTITY='WSL_CLEANUP_IDENTITY_CHANGED';REMOVE_LOCK='LIFECYCLE_LOCK_OWNERSHIP_REQUIRED';REMOVE_CONTAINMENT='WSL_GUARDED_COMMAND_CONTAINMENT_FAILED';REMOVE_UNKNOWN='untrusted raw failure'
    }
    if($removeFailures.ContainsKey($script:Scenario)){throw $removeFailures[$script:Scenario]}
    if($script:Scenario -ceq 'REMOVE_EXIT_ONE'){return [pscustomobject]@{ExitCode=1;Output=''}}
    return [pscustomobject]@{ExitCode=0;Output=''}
   }
   if($Arguments[0] -ceq '/usr/bin/test'){
    if($script:Scenario -ceq 'REMOVE_TIMEOUT_ABSENCE_THROW'){throw 'WSL_COMMAND_TIMEOUT'}
    return [pscustomobject]@{ExitCode=if($script:Scenario -cin @('ABSENCE_FALSE','REMOVE_TIMEOUT_ABSENCE_FALSE')){1}else{0};Output=''}
   }
   throw 'UNEXPECTED_TEST_COMMAND'
  }
  . ([scriptblock]::Create($Definition))
 }
 $credentialTestLock=[Threading.Mutex]::new($false)
 try{
  $credentialPath='/run/thrivelens-r0-auth-0123456789abcdef0123456789abcdef.pgpass'
  $runCredentialCase={param([string]$scenario)& $credentialTestModule {param($scenario,$token,$lock,$path)$script:Scenario=$scenario;$script:IdentityAssertCalls=0;$script:GuardedCalls=0;$script:ConfigurationPreserved=$true;$script:CallLog.Clear();$script:ExpectedContract=[pscustomobject]@{Name='contract'};$paths=[pscustomobject]@{Name='paths'};$result=Remove-ThriveLensRuntimeCredential -Path $path -IdentityToken $token -LifecycleLock $lock -Contract $script:ExpectedContract -Paths $paths;[pscustomobject]@{Result=$result;IdentityCalls=$script:IdentityAssertCalls;GuardedCalls=$script:GuardedCalls;ConfigurationPreserved=$script:ConfigurationPreserved;Log=@($script:CallLog)}} $scenario $identityToken $credentialTestLock $credentialPath}
  $successCase=& $runCredentialCase 'SUCCESS';A ($successCase.Result.RemoveSucceeded -and $successCase.Result.CredentialAbsenceVerified -and $successCase.IdentityCalls -eq 2 -and $successCase.GuardedCalls -eq 2 -and ($successCase.Log -join ',') -ceq ("/usr/bin/rm|$credentialPath,/usr/bin/test|$credentialPath")) 'CREDENTIAL_EXECUTABLE_SUCCESS_EXACT_ORDER'
  $removeExitCase=& $runCredentialCase 'REMOVE_EXIT_ONE';A (-not $removeExitCase.Result.RemoveSucceeded -and $removeExitCase.Result.CredentialAbsenceVerified -and $removeExitCase.Result.FailureCode -ceq 'AUTH_FILE_CLEANUP_REMOVE_FAILED' -and $removeExitCase.Result.RootFailureCode -ceq 'AUTH_FILE_CLEANUP_REMOVE_FAILED' -and $removeExitCase.IdentityCalls -eq 2 -and $removeExitCase.GuardedCalls -eq 2) 'CREDENTIAL_EXECUTABLE_REMOVE_EXIT_THEN_ABSENCE'
  $safeFailureCodes=@{REMOVE_TIMEOUT='WSL_COMMAND_TIMEOUT';REMOVE_OUTPUT_LIMIT='WSL_OUTPUT_LIMIT_EXCEEDED';REMOVE_DRAIN='WSL_OUTPUT_DRAIN_INCOMPLETE';REMOVE_START='WSL_PROCESS_START_FAILED'}
  foreach($safeScenario in $safeFailureCodes.Keys){$safeCase=& $runCredentialCase $safeScenario;A (-not $safeCase.Result.RemoveSucceeded -and $safeCase.Result.CredentialAbsenceVerified -and $safeCase.Result.FailureCode -ceq 'AUTH_FILE_CLEANUP_REMOVE_FAILED' -and $safeCase.Result.RootFailureCode -ceq $safeFailureCodes[$safeScenario] -and $safeCase.IdentityCalls -eq 2 -and $safeCase.GuardedCalls -eq 2 -and ($safeCase.Log -join ',') -ceq ("/usr/bin/rm|$credentialPath,/usr/bin/test|$credentialPath")) 'CREDENTIAL_EXECUTABLE_SAFE_THROW_THEN_EXACT_ABSENCE'}
  $safeFalseCase=& $runCredentialCase 'REMOVE_TIMEOUT_ABSENCE_FALSE';A (-not $safeFalseCase.Result.CredentialAbsenceVerified -and $safeFalseCase.Result.FailureCode -ceq 'AUTH_FILE_CLEANUP_ABSENCE_UNVERIFIED' -and $safeFalseCase.Result.RootFailureCode -ceq 'WSL_COMMAND_TIMEOUT' -and $safeFalseCase.IdentityCalls -eq 2 -and $safeFalseCase.GuardedCalls -eq 2) 'CREDENTIAL_EXECUTABLE_SAFE_THROW_FALSE_ABSENCE'
  $safeThrowCase=& $runCredentialCase 'REMOVE_TIMEOUT_ABSENCE_THROW';A (-not $safeThrowCase.Result.CredentialAbsenceVerified -and $safeThrowCase.Result.FailureCode -ceq 'AUTH_FILE_CLEANUP_ABSENCE_UNVERIFIED' -and $safeThrowCase.Result.RootFailureCode -ceq 'WSL_COMMAND_TIMEOUT' -and $safeThrowCase.IdentityCalls -eq 2 -and $safeThrowCase.GuardedCalls -eq 2) 'CREDENTIAL_EXECUTABLE_SAFE_THROW_ABSENCE_THROW'
  $unsafeRemoveCodes=@{REMOVE_IDENTITY='WSL_CLEANUP_IDENTITY_CHANGED';REMOVE_LOCK='LIFECYCLE_LOCK_OWNERSHIP_REQUIRED';REMOVE_CONTAINMENT='WSL_GUARDED_COMMAND_CONTAINMENT_FAILED';REMOVE_UNKNOWN='RUNTIME_TEST_INTERNAL_ERROR'}
  foreach($unsafeScenario in $unsafeRemoveCodes.Keys){$unsafeCase=& $runCredentialCase $unsafeScenario;A (-not $unsafeCase.Result.CredentialAbsenceVerified -and $unsafeCase.Result.FailureCode -ceq 'AUTH_FILE_CLEANUP_ABSENCE_UNVERIFIED' -and $unsafeCase.Result.RootFailureCode -ceq $unsafeRemoveCodes[$unsafeScenario] -and $unsafeCase.IdentityCalls -eq 1 -and $unsafeCase.GuardedCalls -eq 1 -and $unsafeCase.Log[0] -ceq "/usr/bin/rm|$credentialPath") 'CREDENTIAL_EXECUTABLE_UNSAFE_REMOVE_ZERO_FOLLOW_ON'}
  $assertFailureCodes=@{ASSERT_IDENTITY='WSL_CLEANUP_IDENTITY_CHANGED';ASSERT_LOCK='LIFECYCLE_LOCK_OWNERSHIP_REQUIRED';ASSERT_CONTAINMENT='WSL_GUARDED_COMMAND_CONTAINMENT_FAILED';ASSERT_UNKNOWN='RUNTIME_TEST_INTERNAL_ERROR'}
  foreach($assertScenario in $assertFailureCodes.Keys){$assertFailureCase=& $runCredentialCase $assertScenario;A (-not $assertFailureCase.Result.CredentialAbsenceVerified -and $assertFailureCase.Result.FailureCode -ceq 'AUTH_FILE_CLEANUP_ABSENCE_UNVERIFIED' -and $assertFailureCase.Result.RootFailureCode -ceq $assertFailureCodes[$assertScenario] -and $assertFailureCase.IdentityCalls -eq 1 -and $assertFailureCase.GuardedCalls -eq 0) 'CREDENTIAL_EXECUTABLE_ASSERT_FAILURE_ZERO_GUEST_CALLS'}
  $absenceFalseCase=& $runCredentialCase 'ABSENCE_FALSE';A ($absenceFalseCase.Result.RemoveSucceeded -and -not $absenceFalseCase.Result.CredentialAbsenceVerified -and $absenceFalseCase.Result.FailureCode -ceq 'AUTH_FILE_CLEANUP_ABSENCE_UNVERIFIED' -and $absenceFalseCase.Result.RootFailureCode -ceq 'AUTH_FILE_CLEANUP_ABSENCE_UNVERIFIED' -and $absenceFalseCase.IdentityCalls -eq 2 -and $absenceFalseCase.GuardedCalls -eq 2) 'CREDENTIAL_EXECUTABLE_FALSE_ABSENCE_REJECTED'
 }finally{$credentialTestLock.Dispose();Remove-Module $credentialTestModule -Force -ErrorAction SilentlyContinue}
 A ($runtimeTest -match 'Read-ThriveLensPostgresBootstrapSecret\s+-Path\s+\$actual') 'RUNTIME_PROTECTED_SECRET_READER'
 A ($runtimeTest -match 'SCRAM_AUTH_PROBE_FAILED') 'RUNTIME_POSITIVE_AUTH_MARKER'
 A ($runtimeTest -match 'Assert-ThriveLensClusterScramConfig') 'RUNTIME_HBA_MARKER'
 A ($runtimeTest -match 'PASSWORD_ENCRYPTION_PROBE_FAILED') 'RUNTIME_PASSWORD_ENCRYPTION_MARKER'
 A ($runtimeTest -match 'SCRAM_VERIFIER_PROBE_FAILED') 'RUNTIME_VERIFIER_MARKER'
 A ($runtimeTest -match 'Resolve-ThriveLensWrongPasswordProbe' -and $runtimeTest -match 'CapturePrivateStandardError' -and $runtimeTest -match "'LC_ALL=C'") 'RUNTIME_WRONG_PASSWORD_CLASSIFIER'
 $guardedCalls=@($runtimeAst.FindAll({param($node)$node -is [Management.Automation.Language.CommandAst] -and $node.GetCommandName() -ceq 'Invoke-ThriveLensGuardedDistro'},$true))
 $positiveProbeTokens=@("'/usr/sbin/runuser'","'-u'","'postgres'","'--'","'/usr/bin/env'","'-i'",'"PGPASSFILE=$AuthFile"',"'PGCONNECT_TIMEOUT=5'","'PGREQUIREAUTH=scram-sha-256'","'/usr/bin/psql'","'-X'","'-w'","'-h'","'127.0.0.1'","'-p'",'([string]$Paths.Port)',"'-U'","'tl_bootstrap'","'-d'","'postgres'","'-Atq'","'--set=ON_ERROR_STOP=1'","'--command'",'$Sql')
 $wrongProbeTokens=@("'/usr/sbin/runuser'","'-u'","'postgres'","'--'","'/usr/bin/env'","'-i'","'LC_ALL=C'","'LANG=C'",'"PGPASSFILE=$wrongAuthFile"',"'PGCONNECT_TIMEOUT=5'","'PGREQUIREAUTH=scram-sha-256'","'/usr/bin/psql'","'-X'","'-w'","'-h'","'127.0.0.1'","'-p'",'([string]$leasedPaths.Port)',"'-U'","'tl_bootstrap'","'-d'","'postgres'","'-Atq'","'--set=ON_ERROR_STOP=1'","'--command'","'SELECT 1'")
 $wrongInstallTokens=@("'/usr/bin/install'","'-o'","'postgres'","'-g'","'postgres'","'-m'","'0600'","'/dev/stdin'",'$wrongAuthFile')
 $positiveProbeCalls=@($guardedCalls|Where-Object{((Get-ArrayArgumentTokenText -Command $_ -ParameterName 'Arguments')-join "`n") -ceq ($positiveProbeTokens-join "`n")})
 $wrongProbeCalls=@($guardedCalls|Where-Object{((Get-ArrayArgumentTokenText -Command $_ -ParameterName 'Arguments')-join "`n") -ceq ($wrongProbeTokens-join "`n")})
 $wrongInstallCalls=@($guardedCalls|Where-Object{((Get-ArrayArgumentTokenText -Command $_ -ParameterName 'Arguments')-join "`n") -ceq ($wrongInstallTokens-join "`n")})
 A ($positiveProbeCalls.Count -eq 1 -and $wrongProbeCalls.Count -eq 1 -and $wrongInstallCalls.Count -eq 1) 'RUNTIME_EXACT_SCRAM_PROBE_ARGUMENT_ASTS'
 $wrongProbeAst=$wrongProbeCalls[0];$wrongInstallAst=$wrongInstallCalls[0]
 A (@($wrongProbeAst.CommandElements|Where-Object{$_ -is [Management.Automation.Language.CommandParameterAst] -and $_.ParameterName -ceq 'CapturePrivateStandardError'}).Count -eq 1) 'RUNTIME_WRONG_PROBE_PRIVATE_STDERR_AST'
 $wrongProbeIndex=$wrongProbeAst.Extent.StartOffset
 $wrongCredentialDeleteIndex=$runtimeTest.IndexOf('Remove-ThriveLensRuntimeCredential -Path $wrongAuthFile',$wrongProbeIndex);$usabilityFalseIndex=$runtimeTest.IndexOf('$serverUsableAfterWrong=$false',$wrongCredentialDeleteIndex);$usabilityQueryIndex=$runtimeTest.IndexOf("-FailureCode 'WRONG_PASSWORD_SERVER_USABILITY_UNVERIFIED'",$usabilityFalseIndex);$usabilityTrueIndex=$runtimeTest.IndexOf('$serverUsableAfterWrong=$true',$usabilityQueryIndex);$classifierIndex=$runtimeTest.IndexOf('$wrongOutcome=Resolve-ThriveLensWrongPasswordProbe',$usabilityTrueIndex)
 A ($wrongProbeIndex -ge 0 -and $usabilityFalseIndex -gt $wrongProbeIndex -and $usabilityQueryIndex -gt $usabilityFalseIndex -and $usabilityTrueIndex -gt $usabilityQueryIndex -and $classifierIndex -gt $usabilityTrueIndex -and $runtimeTest.Substring($classifierIndex,[Math]::Min(500,$runtimeTest.Length-$classifierIndex)) -match '-ServerUsableAfterProbe \$serverUsableAfterWrong') 'RUNTIME_WRONG_PASSWORD_USABILITY_ORDERED'
 $expectedPathBindingIndex=$runtimeTest.IndexOf('-ExpectedPasswordFile $wrongAuthFile',$classifierIndex);$wrongPathClearIndex=$runtimeTest.IndexOf('$wrongAuthFile=$null',$expectedPathBindingIndex)
 $wrongRemoveCalls=@($runtimeAst.FindAll({param($node)$node -is [Management.Automation.Language.CommandAst] -and $node.GetCommandName() -ceq 'Remove-ThriveLensRuntimeCredential' -and $node.Extent.Text -match '-Path\s+\$wrongAuthFile(?:\s|$)'},$true))
 $wrongClassifierCalls=@($runtimeAst.FindAll({param($node)$node -is [Management.Automation.Language.CommandAst] -and $node.GetCommandName() -ceq 'Resolve-ThriveLensWrongPasswordProbe' -and $node.Extent.Text -match '-ExpectedPasswordFile\s+\$wrongAuthFile(?:\s|$)'},$true))
 $wrongClears=@($runtimeAst.FindAll({param($node)$node -is [Management.Automation.Language.AssignmentStatementAst] -and $node.Left.Extent.Text -ceq '$wrongAuthFile' -and $node.Right.Extent.Text -ceq '$null'},$true)|Where-Object{$_.Extent.StartOffset -gt $wrongInstallAst.Extent.StartOffset})
 A ($wrongRemoveCalls.Count -eq 1 -and $wrongClassifierCalls.Count -eq 1 -and $wrongClears.Count -ge 1 -and $wrongInstallAst.Extent.StartOffset -lt $wrongProbeAst.Extent.StartOffset -and $wrongProbeAst.Extent.StartOffset -lt $wrongRemoveCalls[0].Extent.StartOffset -and $wrongRemoveCalls[0].Extent.StartOffset -lt $wrongClassifierCalls[0].Extent.StartOffset -and $wrongClassifierCalls[0].Extent.StartOffset -lt $wrongClears[0].Extent.StartOffset -and $runtimeTest.Substring($wrongInstallAst.Extent.StartOffset,$wrongClassifierCalls[0].Extent.StartOffset-$wrongInstallAst.Extent.StartOffset) -notmatch '\$wrongAuthFile\s*=\s*\$null') 'RUNTIME_WRONG_PASSWORD_PATH_PRIVATE_LIFETIME'
 A (Test-ThriveLensRuntimeAdapterContract -Source $runtimeTest) 'RUNTIME_IN_PROCESS_TRANSACTION_CONTRACT'
 $policyMaxMutation=Replace-ThriveLensTestSourceOnce -Source $runtimeTest -Old 'return [Math]::Max($validatedValues[0], $validatedValues[1])' -New 'return [Math]::Min($validatedValues[0], $validatedValues[1])'
 A ((Test-ThriveLensSourceParses -Source $policyMaxMutation) -and -not (Test-ThriveLensRuntimeAdapterContract -Source $policyMaxMutation)) 'MUTATION_KILLS_INTER_CYCLE_POLICY_MIN'
 $policyRuntimeOnlyMutation=Replace-ThriveLensTestSourceOnce -Source $runtimeTest -Old 'return [Math]::Max($validatedValues[0], $validatedValues[1])' -New 'return $validatedValues[0]'
 A ((Test-ThriveLensSourceParses -Source $policyRuntimeOnlyMutation) -and -not (Test-ThriveLensRuntimeAdapterContract -Source $policyRuntimeOnlyMutation)) 'MUTATION_KILLS_INTER_CYCLE_POLICY_RUNTIME_ONLY'
 $policyHardcodeMutation=Replace-ThriveLensTestSourceOnce -Source $runtimeTest -Old 'return [Math]::Max($validatedValues[0], $validatedValues[1])' -New 'return [int64]2147483648'
 A ((Test-ThriveLensSourceParses -Source $policyHardcodeMutation) -and -not (Test-ThriveLensRuntimeAdapterContract -Source $policyHardcodeMutation)) 'MUTATION_KILLS_INTER_CYCLE_POLICY_HARDCODE'
 $policyTypeMutation=Replace-ThriveLensTestSourceOnce -Source $runtimeTest -Old '$candidateValues[0] -isnot [int64]' -New '$candidateValues[0] -is [bool]'
 A ((Test-ThriveLensSourceParses -Source $policyTypeMutation) -and -not (Test-ThriveLensRuntimeAdapterContract -Source $policyTypeMutation)) 'MUTATION_KILLS_INTER_CYCLE_POLICY_NON_INT64_ACCEPTANCE'
 $removedContractClear=Replace-ThriveLensTestSourceOccurrence -Source $runtimeTest -Old '$leasedContract = $null' -New '$null = $leasedContract' -Occurrence 3
 A ((Test-ThriveLensSourceParses -Source $removedContractClear) -and -not (Test-ThriveLensRuntimeAdapterContract -Source $removedContractClear)) 'MUTATION_KILLS_INTER_CYCLE_CONTRACT_CLEAR_REMOVAL'
 $removedPathsClear=Replace-ThriveLensTestSourceOccurrence -Source $runtimeTest -Old '$leasedPaths = $null' -New '$null = $leasedPaths' -Occurrence 3
 A ((Test-ThriveLensSourceParses -Source $removedPathsClear) -and -not (Test-ThriveLensRuntimeAdapterContract -Source $removedPathsClear)) 'MUTATION_KILLS_INTER_CYCLE_PATHS_CLEAR_REMOVAL'
 $runtimeCoreCalls=Get-ThriveLensCommandAsts -Ast $runtimeAst -Name 'Invoke-ThriveLensPostgresStartUnderLock';$runtimeTokenCalls=Get-ThriveLensCommandAsts -Ast $runtimeAst -Name 'Get-ThriveLensWslCleanupIdentityToken';$settleCalls=Get-ThriveLensCommandAsts -Ast $runtimeAst -Name 'Wait-ThriveLensInterCycleMemorySettle'
 A ($runtimeCoreCalls.Count -eq 1 -and $runtimeTokenCalls.Count -eq 1 -and $settleCalls.Count -eq 1) 'RUNTIME_ONE_CORE_AND_TOKEN_PER_LEXICAL_CYCLE'
 A ($runtimeTest -notmatch '(?i)pwsh(?:\.exe)?\s+.*(?:preflight|start|stop)\.ps1|Start-Process|Resolve-ThriveLens(?:ChildOutcome|StartChildExit|PreTokenStartObservation)') 'RUNTIME_NO_CHILD_RUNNER_PRETOKEN_OR_FRESH_TOKEN_BRANCH'
 A ($runtimeTest -notmatch 'Invoke-ThriveLensDistro' -and $runtimeTest -match 'Invoke-ThriveLensGuardedDistro') 'RUNTIME_ONLY_GUARDED_DISTRO_CALLS'
 A ($runtimeTest -match '\$completedCycles\s*-ne\s*2' -and $runtimeTest -match 'real_postgresql\s*=\s*\(\$completedCycles\s*-eq\s*2\)' -and $runtimeTest -match 'cycles\s*=\s*\$completedCycles') 'RUNTIME_COMMAND3_PASS_COMPLETED_CYCLE_DERIVED'
 A ($runtimeTest -match 'Resolve-ThriveLensRuntimeCleanupOutcome' -and $runtimeTest -match 'schema_version = 2' -and $runtimeTest -match 'original_code' -and $runtimeTest -match 'failure_stages' -and $runtimeTest -match 'credential_absence_verified') 'RUNTIME_CLOSED_FAILURE_SCHEMA_V2'

 $coreMemoryGuard=@($startCoreAst.FindAll({param($node)$node -is [Management.Automation.Language.IfStatementAst] -and @($node.Clauses|Where-Object{$_.Item1.Extent.Text -match '^\s*\$freeMemoryBytes\s*-lt\s*\$runtimeMinimumBytes\s*$'}).Count -gt 0},$true))[0]
 $coreGuardMutation=Replace-ThriveLensTestAstExtent -Source $module -Extent $coreMemoryGuard.Clauses[0].Item1.Extent -New '$freeMemoryBytes -ge $runtimeMinimumBytes'
 A ((Test-ThriveLensSourceParses -Source $coreGuardMutation) -and -not (Test-ThriveLensStartCoreContract -Source $coreGuardMutation)) 'MUTATION_KILLS_CORE_RAM_GUARD_POLARITY'
 $coreHardcodedMutation=Replace-ThriveLensTestSourceOnce -Source $module -Old '$memoryPolicy.StartReclaimTargetBytes' -New '[int64]1073741824'
 A ((Test-ThriveLensSourceParses -Source $coreHardcodedMutation) -and -not (Test-ThriveLensStartCoreContract -Source $coreHardcodedMutation)) 'MUTATION_KILLS_CORE_HARDCODED_THRESHOLD'
 $memoryPolicyMinMutation=Replace-ThriveLensTestSourceOnce -Source $runtimeModule -Old '[int64][Math]::Max($validatedValues[0], $validatedValues[1])' -New '[int64][Math]::Min($validatedValues[0], $validatedValues[1])'
 A ((Test-ThriveLensSourceParses -Source $memoryPolicyMinMutation) -and -not (Test-ThriveLensMemoryPolicyContract -Source $memoryPolicyMinMutation)) 'MUTATION_KILLS_START_RECLAIM_POLICY_MIN'
 $memoryPolicyRuntimeOnlyMutation=Replace-ThriveLensTestSourceOnce -Source $runtimeModule -Old '[int64][Math]::Max($validatedValues[0], $validatedValues[1])' -New '[int64]$validatedValues[0]'
 A ((Test-ThriveLensSourceParses -Source $memoryPolicyRuntimeOnlyMutation) -and -not (Test-ThriveLensMemoryPolicyContract -Source $memoryPolicyRuntimeOnlyMutation)) 'MUTATION_KILLS_START_RECLAIM_POLICY_RUNTIME_ONLY'
 $memoryPolicyHardcodeMutation=Replace-ThriveLensTestSourceOnce -Source $runtimeModule -Old '[int64][Math]::Max($validatedValues[0], $validatedValues[1])' -New '[int64]2147483648'
 A ((Test-ThriveLensSourceParses -Source $memoryPolicyHardcodeMutation) -and -not (Test-ThriveLensMemoryPolicyContract -Source $memoryPolicyHardcodeMutation)) 'MUTATION_KILLS_START_RECLAIM_POLICY_HARDCODE'
 $memoryPolicyTypeMutation=Replace-ThriveLensTestSourceOnce -Source $runtimeModule -Old '$candidateValues[0] -isnot [int64]' -New '$candidateValues[0] -is [bool]'
 A ((Test-ThriveLensSourceParses -Source $memoryPolicyTypeMutation) -and -not (Test-ThriveLensMemoryPolicyContract -Source $memoryPolicyTypeMutation)) 'MUTATION_KILLS_START_RECLAIM_POLICY_NON_INT64_ACCEPTANCE'
 $corePolicyRereadMutation=Replace-ThriveLensTestSourceOnce -Source $module -Old 'Get-ThriveLensWslContract -ConfigurationLease $ConfigurationLease' -New 'Get-ThriveLensWslContract'
 A ((Test-ThriveLensSourceParses -Source $corePolicyRereadMutation) -and -not (Test-ThriveLensStartCoreContract -Source $corePolicyRereadMutation)) 'MUTATION_KILLS_CORE_POLICY_REREAD'
 $identityAssignment=@($startCoreAst.FindAll({param($node)$node -is [Management.Automation.Language.AssignmentStatementAst] -and $node.Extent.Text -match '^\$null\s*=\s*Assert-ThriveLensWslIdentity'},$true))[0];$packageAssignment=@($startCoreAst.FindAll({param($node)$node -is [Management.Automation.Language.AssignmentStatementAst] -and $node.Extent.Text -match '^\$null\s*=\s*Assert-ThriveLensWslPackages'},$true))[0]
 $coreOrderMutation=$module.Substring(0,$identityAssignment.Extent.StartOffset)+$packageAssignment.Extent.Text+"`n        "+$identityAssignment.Extent.Text+$module.Substring($packageAssignment.Extent.EndOffset)
 A ((Test-ThriveLensSourceParses -Source $coreOrderMutation) -and -not (Test-ThriveLensStartCoreContract -Source $coreOrderMutation)) 'MUTATION_KILLS_CORE_IDENTITY_PACKAGE_ORDER'
 $attemptFlag=@($startCoreAst.FindAll({param($node)$node -is [Management.Automation.Language.AssignmentStatementAst] -and $node.Left.Extent.Text -ceq '$StartAttempted.Value'},$true))[0]
 $coreAdjacencyMutation=$module.Insert($attemptFlag.Extent.EndOffset,"`n        `$null=Assert-ThriveLensConfigurationLease -Lease `$ConfigurationLease")
 A ((Test-ThriveLensSourceParses -Source $coreAdjacencyMutation) -and -not (Test-ThriveLensStartCoreContract -Source $coreAdjacencyMutation)) 'MUTATION_KILLS_CORE_ATTEMPTED_ADJACENCY'
 $corePreStartForce=Get-ThriveLensCommandAsts -Ast $startCoreAst -Name 'Stop-ThriveLensDistroAndVerify'
 if($corePreStartForce.Count -eq 1){$coreSkippedPreStartForce=Replace-ThriveLensTestAstExtent -Source $module -Extent $corePreStartForce[0].Extent -New 'Write-Output $null';A ((Test-ThriveLensSourceParses -Source $coreSkippedPreStartForce) -and -not (Test-ThriveLensStartCoreContract -Source $coreSkippedPreStartForce)) 'MUTATION_KILLS_CORE_PRESTART_EXACT_TERMINATION_REMOVAL'}else{A $false 'MUTATION_KILLS_CORE_PRESTART_EXACT_TERMINATION_REMOVAL'}
 $coreSettleCalls=Get-ThriveLensCommandAsts -Ast $startCoreAst -Name 'Wait-ThriveLensInterCycleMemorySettle'
 if($coreSettleCalls.Count -eq 1){$coreSkippedSettle=Replace-ThriveLensTestAstExtent -Source $module -Extent $coreSettleCalls[0].Extent -New 'Write-Output $null';A ((Test-ThriveLensSourceParses -Source $coreSkippedSettle) -and -not (Test-ThriveLensStartCoreContract -Source $coreSkippedSettle)) 'MUTATION_KILLS_CORE_PRESTART_SETTLE_REMOVAL'}else{A $false 'MUTATION_KILLS_CORE_PRESTART_SETTLE_REMOVAL'}
 $coreIdentityFences=Get-ThriveLensCommandAsts -Ast $startCoreAst -Name 'Assert-ThriveLensWslIdentity'
 if($coreIdentityFences.Count -eq 2){$coreSkippedIdentityFence=Replace-ThriveLensTestAstExtent -Source $module -Extent $coreIdentityFences[1].Extent -New 'Write-Output $null';A ((Test-ThriveLensSourceParses -Source $coreSkippedIdentityFence) -and -not (Test-ThriveLensStartCoreContract -Source $coreSkippedIdentityFence)) 'MUTATION_KILLS_CORE_FINAL_IDENTITY_FENCE_REMOVAL'}else{A $false 'MUTATION_KILLS_CORE_FINAL_IDENTITY_FENCE_REMOVAL'}
 $coreAuthorityReassignment=$module.Insert($corePreStartForce[0].Extent.StartOffset,"`$IdentityToken=[pscustomobject]@{Replacement=`$true}`n        ")
 A ((Test-ThriveLensSourceParses -Source $coreAuthorityReassignment) -and -not (Test-ThriveLensStartCoreContract -Source $coreAuthorityReassignment)) 'MUTATION_KILLS_CORE_IDENTITY_TOKEN_REASSIGNMENT'
 foreach($authorityMutation in @(
  [pscustomobject]@{Code='MUTATION_KILLS_CORE_TERMINATE_TOKEN_CLONE';Offset=$corePreStartForce[0].Extent.StartOffset;Text='$IdentityToken=$IdentityToken.PSObject.Copy()'},
  [pscustomobject]@{Code='MUTATION_KILLS_CORE_FINAL_LEASE_CLONE';Offset=$coreSettleCalls[0].Extent.EndOffset;Text='$ConfigurationLease=$ConfigurationLease.PSObject.Copy()'},
  [pscustomobject]@{Code='MUTATION_KILLS_CORE_FINAL_CONTRACT_CLONE';Offset=$coreIdentityFences[1].Extent.StartOffset;Text='$leasedContract=$leasedContract.PSObject.Copy()'},
  [pscustomobject]@{Code='MUTATION_KILLS_CORE_PGCTL_TOKEN_CLONE';Offset=$attemptFlag.Extent.StartOffset;Text='$IdentityToken=$IdentityToken.PSObject.Copy()'}
 )){$mutant=$module.Insert($authorityMutation.Offset,("`n        "+$authorityMutation.Text+"`n        "));A (Test-ThriveLensSourceParses -Source $mutant) ($authorityMutation.Code+'_PARSES');if(Test-ThriveLensSourceParses -Source $mutant){$result=Invoke-ThriveLensStartCoreHarness -Definition (Get-ThriveLensFunctionAst -Ast (Get-ThriveLensParsedSource -Source $mutant).Ast -Name 'Invoke-ThriveLensPostgresStartUnderLock').Extent.Text -Mode 'SUCCESS';A ($null -ne $result.Code -and -not $result.StartCommitResourceGateVerified) $authorityMutation.Code}}
 $coreCommandGap=$module.Insert($attemptFlag.Extent.StartOffset,"Write-Output 'gap'`n        ")
 A ((Test-ThriveLensSourceParses -Source $coreCommandGap) -and -not (Test-ThriveLensStartCoreContract -Source $coreCommandGap)) 'MUTATION_KILLS_CORE_EXTERNAL_COMMAND_BEFORE_PGCTL'
 $coreProcessGap=$module.Insert($attemptFlag.Extent.StartOffset,"if(`$false){[System.Diagnostics.Process]::Start('synthetic')}`n        ")
 A ((Test-ThriveLensSourceParses -Source $coreProcessGap) -and -not (Test-ThriveLensStartCoreContract -Source $coreProcessGap)) 'MUTATION_KILLS_CORE_PROCESS_MEMBER_INVOCATION_BEFORE_PGCTL'
 $settleProcessMutation=$runtimeModule.Insert($settleFunctions[0].Body.EndBlock.Statements[0].Extent.StartOffset,"if(`$false){[System.Diagnostics.Process]::Start('synthetic')}`n ")
 A ((Test-ThriveLensSourceParses -Source $settleProcessMutation) -and -not (Test-ThriveLensSettleHostOnlyContract -Source $settleProcessMutation)) 'MUTATION_KILLS_SETTLE_PROCESS_MEMBER_INVOCATION'
 $oldChildMutation=$module+"`nResolve-ThriveLensStartChildExit -ExitCode 2"
 A ((Test-ThriveLensSourceParses -Source $oldChildMutation) -and -not (Test-ThriveLensStartCoreContract -Source $oldChildMutation)) 'MUTATION_KILLS_OLD_CHILD_SYMBOL'

 A (Test-ThriveLensWslRunnerContract -Source $module) 'WSL_RUNNER_EXACT_FAILURE_CONTAINMENT_CONTRACT'
 $wslRunnerMutations=@(
  [pscustomobject]@{Code='MUTATION_KILLS_WSL_RUNNER_ROOT_KILL_REMOVAL';Old='if(-not $process.HasExited){$process.Kill($true)}';New='if($false){$process.Kill($true)}'},
  [pscustomobject]@{Code='MUTATION_KILLS_WSL_RUNNER_ROOT_REAP_INVERSION';Old='if(-not $rootReaped){$cleanupProven=$false}';New='if($rootReaped){$cleanupProven=$false}'},
  [pscustomobject]@{Code='MUTATION_KILLS_WSL_RUNNER_ROOT_HAS_EXITED_PROOF';Old='if($rootReaped){$rootReaped=$process.HasExited}';New='if($rootReaped){$rootReaped=$true}'},
  [pscustomobject]@{Code='MUTATION_KILLS_WSL_RUNNER_STARTED_CLEANUP_GUARD';Old="`$cleanupProven=`$true`n        if(`$started){";New="`$cleanupProven=`$true`n        if(-not `$started){"},
  [pscustomobject]@{Code='MUTATION_KILLS_WSL_RUNNER_CLEANUP_INITIAL_TRUTH';Old='$cleanupProven=$true';New='$cleanupProven=$false'},
  [pscustomobject]@{Code='MUTATION_KILLS_WSL_RUNNER_NULL_TASK_SKIP';Old='if($null -eq $ioTask){continue}';New='if($null -ne $ioTask){continue}'},
  [pscustomobject]@{Code='MUTATION_KILLS_WSL_RUNNER_BOUNDED_TASK_WAIT';Old='$null=$ioTask.Wait(5000)';New='$null=$ioTask.Wait()'},
  [pscustomobject]@{Code='MUTATION_KILLS_WSL_RUNNER_READER_COMPLETION_INVERSION';Old='if(-not $ioTask.IsCompleted){$cleanupProven=$false}';New='if($ioTask.IsCompleted){$cleanupProven=$false}'},
  [pscustomobject]@{Code='MUTATION_KILLS_WSL_RUNNER_UNCERTAINTY_GATE_INVERSION';Old="if(-not `$cleanupProven){throw 'WSL_OUTPUT_DRAIN_INCOMPLETE'}";New="if(`$cleanupProven){throw 'WSL_OUTPUT_DRAIN_INCOMPLETE'}"},
  [pscustomobject]@{Code='MUTATION_KILLS_WSL_RUNNER_MONOTONIC_DEADLINE_REMOVAL';Old='$stopwatch=[Diagnostics.Stopwatch]::StartNew()';New='$stopwatch=[Diagnostics.Stopwatch]::new()'},
  [pscustomobject]@{Code='MUTATION_KILLS_WSL_RUNNER_STDIN_WRITE_SHARED_DEADLINE';Old='($timeoutMilliseconds-$stopwatch.ElapsedMilliseconds)';New='$timeoutMilliseconds';Occurrence=1},
  [pscustomobject]@{Code='MUTATION_KILLS_WSL_RUNNER_STDIN_FLUSH_SHARED_DEADLINE';Old='($timeoutMilliseconds-$stopwatch.ElapsedMilliseconds)';New='$timeoutMilliseconds';Occurrence=2},
  [pscustomobject]@{Code='MUTATION_KILLS_WSL_RUNNER_STDIN_LIMIT_INVERSION';Old='if($stdinBytes.Length -gt 512)';New='if($stdinBytes.Length -le 512)'},
  [pscustomobject]@{Code='MUTATION_KILLS_WSL_RUNNER_STDOUT_TASK_SLOT';Old='@($stdoutTask,$stderrTask,$stdinWriteTask,$stdinFlushTask)';New='@($null,$stderrTask,$stdinWriteTask,$stdinFlushTask)'},
  [pscustomobject]@{Code='MUTATION_KILLS_WSL_RUNNER_STDERR_TASK_SLOT';Old='@($stdoutTask,$stderrTask,$stdinWriteTask,$stdinFlushTask)';New='@($stdoutTask,$null,$stdinWriteTask,$stdinFlushTask)'},
  [pscustomobject]@{Code='MUTATION_KILLS_WSL_RUNNER_STDIN_WRITE_TASK_SLOT';Old='@($stdoutTask,$stderrTask,$stdinWriteTask,$stdinFlushTask)';New='@($stdoutTask,$stderrTask,$null,$stdinFlushTask)'},
  [pscustomobject]@{Code='MUTATION_KILLS_WSL_RUNNER_STDIN_FLUSH_TASK_SLOT';Old='@($stdoutTask,$stderrTask,$stdinWriteTask,$stdinFlushTask)';New='@($stdoutTask,$stderrTask,$stdinWriteTask,$null)'},
  [pscustomobject]@{Code='MUTATION_KILLS_WSL_RUNNER_ACTIVE_STDOUT_SINK_DISPOSAL';Old='if($stdoutComplete){$stdoutSink.Dispose()}';New='$stdoutSink.Dispose()'},
  [pscustomobject]@{Code='MUTATION_KILLS_WSL_RUNNER_ACTIVE_STDERR_SINK_DISPOSAL';Old='if($stderrComplete){$stderrSink.Dispose()}';New='$stderrSink.Dispose()'},
  [pscustomobject]@{Code='MUTATION_KILLS_WSL_RUNNER_PROCESS_COMPLETION_GATE';Old='if($rootInactive -and $stdoutComplete -and $stderrComplete -and $stdinWriteComplete -and $stdinFlushComplete){$process.Dispose()}';New='if($rootInactive){$process.Dispose()}'},
  [pscustomobject]@{Code='MUTATION_KILLS_WSL_RUNNER_PROCESS_INACTIVE_GATE';Old='if($rootInactive -and $stdoutComplete -and $stderrComplete -and $stdinWriteComplete -and $stdinFlushComplete){$process.Dispose()}';New='if($stdoutComplete -and $stderrComplete -and $stdinWriteComplete -and $stdinFlushComplete){$process.Dispose()}'}
 )
 foreach($wslRunnerMutation in $wslRunnerMutations){
  $occurrence=if($null -ne $wslRunnerMutation.PSObject.Properties['Occurrence']){[int]$wslRunnerMutation.Occurrence}else{1}
  $mutant=if($occurrence -eq 1 -and $module.IndexOf($wslRunnerMutation.Old,[StringComparison]::Ordinal) -ge 0 -and $module.IndexOf($wslRunnerMutation.Old,$module.IndexOf($wslRunnerMutation.Old,[StringComparison]::Ordinal)+$wslRunnerMutation.Old.Length,[StringComparison]::Ordinal) -lt 0){Replace-ThriveLensTestSourceOnce -Source $module -Old $wslRunnerMutation.Old -New $wslRunnerMutation.New}else{Replace-ThriveLensTestSourceOccurrence -Source $module -Old $wslRunnerMutation.Old -New $wslRunnerMutation.New -Occurrence $occurrence}
  A ($mutant -cne $module -and (Test-ThriveLensSourceParses -Source $mutant) -and -not (Test-ThriveLensWslRunnerContract -Source $mutant)) $wslRunnerMutation.Code
 }
 $typeVersionMutant=Replace-ThriveLensTestSourceOnce -Source $module -Old "public sealed class OutputBudget { public const int ContractVersion=2;" -New "public sealed class OutputBudget { public const int ContractVersion=1;"
 A ($typeVersionMutant -cne $module -and (Test-ThriveLensSourceParses -Source $typeVersionMutant) -and -not (Test-ThriveLensWslSecurityTypeContract -Source $typeVersionMutant)) 'MUTATION_KILLS_WSL_SECURITY_V2_VERSION_DOWNGRADE'
 $typeOverflowMutant=Replace-ThriveLensTestSourceOnce -Source $module -Old 'if(total>budget.Limit){budget.Exceeded=true;throw new IOException("OUTPUT_LIMIT");}data.Write(buffer,offset,count);' -New 'if(total>budget.Limit){budget.Exceeded=true;}data.Write(buffer,offset,count);'
 A ($typeOverflowMutant -cne $module -and (Test-ThriveLensSourceParses -Source $typeOverflowMutant) -and -not (Test-ThriveLensWslSecurityTypeContract -Source $typeOverflowMutant)) 'MUTATION_KILLS_WSL_SECURITY_V2_OVERFLOW_NO_APPEND'

 $startGuestGuard=@($startAst.FindAll({param($node)$node -is [Management.Automation.Language.IfStatementAst] -and @($node.Clauses|Where-Object{$_.Item1.Extent.Text -match '\$sameTokenAuthority\s*-and\s*\$cleanupLeaseValid\s*-and\s*\$guestCleanupAllowed\s*-and\s*\$attempted'}).Count -gt 0},$true))[0]
 $startGuardMutation=Replace-ThriveLensTestAstExtent -Source $startRaw -Extent $startGuestGuard.Clauses[0].Item1.Extent -New '-not $sameTokenAuthority -and $cleanupLeaseValid -and $guestCleanupAllowed -and $attempted'
 A ((Test-ThriveLensSourceParses -Source $startGuardMutation) -and -not (Test-ThriveLensStartAdapterContract -Source $startGuardMutation)) 'MUTATION_KILLS_START_CLEANUP_GUARD_POLARITY'
 $startAbsenceAssignment=@($startAst.FindAll({param($node)$node -is [Management.Automation.Language.AssignmentStatementAst] -and $node.Left.Extent.Text -ceq '$absenceObservationAuthorized'},$true))[0]
 $startNoContractGuard=Replace-ThriveLensTestAstExtent -Source $startRaw -Extent $startAbsenceAssignment.Right.Extent -New '$null -ne $leasedPaths -and ($forcedTerminationAuthorized -or -not $cleanupRequired)'
 A ((Test-ThriveLensSourceParses -Source $startNoContractGuard) -and -not (Test-ThriveLensStartAdapterContract -Source $startNoContractGuard)) 'MUTATION_KILLS_START_ABSENCE_CONTRACT_GUARD_REMOVAL'
 $startNoPathsGuard=Replace-ThriveLensTestAstExtent -Source $startRaw -Extent $startAbsenceAssignment.Right.Extent -New '$null -ne $leasedContract -and ($forcedTerminationAuthorized -or -not $cleanupRequired)'
 A ((Test-ThriveLensSourceParses -Source $startNoPathsGuard) -and -not (Test-ThriveLensStartAdapterContract -Source $startNoPathsGuard)) 'MUTATION_KILLS_START_ABSENCE_PATHS_GUARD_REMOVAL'
 $startNoConfigurationGuards=Replace-ThriveLensTestAstExtent -Source $startRaw -Extent $startAbsenceAssignment.Right.Extent -New '($forcedTerminationAuthorized -or -not $cleanupRequired)'
 $startNoConfigurationGuardsResult=Invoke-ThriveLensStartAdapterHarness -Source $startNoConfigurationGuards -Mode 'PRE_LEASE_FAIL'
 A ((Test-ThriveLensSourceParses -Source $startNoConfigurationGuards) -and -not (Test-ThriveLensStartAdapterContract -Source $startNoConfigurationGuards) -and
    @($startNoConfigurationGuardsResult.Log) -contains 'DISTRO_ABSENT' -and @($startNoConfigurationGuardsResult.Log) -contains 'HOST_ABSENT') 'MUTATION_KILLS_START_ABSENCE_CONFIGURATION_GUARDS_REMOVAL'
 $startAssignments=@($startAst.FindAll({param($node)$node -is [Management.Automation.Language.AssignmentStatementAst] -and $node.Left.Extent.Text -cin @('$lifecycleLock','$configurationLease') -and $node.Right.Extent.Text -match '^\s*Enter-ThriveLens(?:LifecycleLock|ConfigurationLease)\s*$'},$true)|Sort-Object {$_.Extent.StartOffset})
 $startOrderExtent=[pscustomobject]@{StartOffset=$startAssignments[0].Extent.StartOffset;EndOffset=$startAssignments[1].Extent.EndOffset}
 $startOrderMutation=$startRaw.Substring(0,$startOrderExtent.StartOffset)+$startAssignments[1].Extent.Text+"`n    "+$startAssignments[0].Extent.Text+$startRaw.Substring($startOrderExtent.EndOffset)
 A ((Test-ThriveLensSourceParses -Source $startOrderMutation) -and -not (Test-ThriveLensStartAdapterContract -Source $startOrderMutation)) 'MUTATION_KILLS_START_LOCK_LEASE_ORDER'
 $startForceCalls=Get-ThriveLensCommandAsts -Ast $startAst -Name 'Stop-ThriveLensDistroAndVerify';$startSkippedForce=Replace-ThriveLensTestAstExtent -Source $startRaw -Extent $startForceCalls[0].Extent -New 'Write-Output $null'
 A ((Test-ThriveLensSourceParses -Source $startSkippedForce) -and -not (Test-ThriveLensStartAdapterContract -Source $startSkippedForce)) 'MUTATION_KILLS_START_SKIPPED_FORCED_TERMINATION'
 $startReleaseAssignments=@($startAst.FindAll({param($node)$node -is [Management.Automation.Language.AssignmentStatementAst] -and $node.Left.Extent.Text -ceq '$lockReleaseFailed' -and $node.Right.Extent.Text -ceq '$true'},$true)|Sort-Object {$_.Extent.StartOffset});$startReleaseReset=Replace-ThriveLensTestAstExtent -Source $startRaw -Extent $startReleaseAssignments[0].Extent -New '$lockReleaseFailed = $false'
 $startReleaseResetResult=Invoke-ThriveLensStartAdapterHarness -Source $startReleaseReset -Mode 'LOCK_RELEASE_FAIL'
 A ((Test-ThriveLensSourceParses -Source $startReleaseReset) -and -not (Test-ThriveLensStartAdapterContract -Source $startReleaseReset) -and
    @($startReleaseResetResult.Log|Where-Object{$_ -ceq 'LOCK_RELEASE'}).Count -eq 1 -and
     $startReleaseResetResult.Adapter.Response.code -ceq 'POST_MUTATION_RESOURCE_GATE_FAILED' -and
    $startReleaseResetResult.Adapter.Response.lifecycle_lock_release_attempted -and -not $startReleaseResetResult.Adapter.Response.lifecycle_lock_released) 'MUTATION_KILLS_START_RELEASE_FLAG_RESET'

 $runtimeCycleGuard=@($runtimeAst.FindAll({param($node)$node -is [Management.Automation.Language.IfStatementAst] -and @($node.Clauses|Where-Object{$_.Item1.Extent.Text -match '^\s*-not\s+\$cycleComplete\s*$'}).Count -gt 0},$true))[0]
 $runtimeGuardMutation=Replace-ThriveLensTestAstExtent -Source $runtimeTest -Extent $runtimeCycleGuard.Clauses[0].Item1.Extent -New '$cycleComplete'
 A ((Test-ThriveLensSourceParses -Source $runtimeGuardMutation) -and -not (Test-ThriveLensRuntimeAdapterContract -Source $runtimeGuardMutation)) 'MUTATION_KILLS_RUNTIME_COMPLETED_CYCLE_GUARD_POLARITY'
 $runtimePolicyRereadMutation=Replace-ThriveLensTestSourceOnce -Source $runtimeTest -Old 'Get-ThriveLensWslContract -ConfigurationLease $configurationLease' -New 'Get-ThriveLensWslContract'
 A ((Test-ThriveLensSourceParses -Source $runtimePolicyRereadMutation) -and -not (Test-ThriveLensRuntimeAdapterContract -Source $runtimePolicyRereadMutation)) 'MUTATION_KILLS_RUNTIME_POLICY_REREAD'
 $runtimeCycle=@($runtimeAst.FindAll({param($node)$node -is [Management.Automation.Language.ForEachStatementAst] -and $node.Variable.VariablePath.UserPath -ceq 'cycle'},$true))[0]
 $runtimeSuccessForce=@((Get-ThriveLensCommandAsts -Ast $runtimeAst -Name 'Stop-ThriveLensDistroAndVerify')|Where-Object{$_.Extent.StartOffset -gt $runtimeCycle.Extent.StartOffset -and $_.Extent.EndOffset -lt $runtimeCycle.Extent.EndOffset})[0]
 $runtimeSkippedForce=Replace-ThriveLensTestAstExtent -Source $runtimeTest -Extent $runtimeSuccessForce.Extent -New 'Write-Output $null'
 A ((Test-ThriveLensSourceParses -Source $runtimeSkippedForce) -and -not (Test-ThriveLensRuntimeAdapterContract -Source $runtimeSkippedForce)) 'MUTATION_KILLS_RUNTIME_SKIPPED_FORCED_TERMINATION'
 $runtimeCatch=@($runtimeAst.EndBlock.Statements|Where-Object{$_ -is [Management.Automation.Language.TryStatementAst]})[0].CatchClauses[0]
 $runtimeResetMutation=$runtimeTest.Insert($runtimeCatch.Body.Extent.StartOffset+1,"`n    `$lockReleaseFailed = `$false")
 A ((Test-ThriveLensSourceParses -Source $runtimeResetMutation) -and -not (Test-ThriveLensRuntimeAdapterContract -Source $runtimeResetMutation)) 'MUTATION_KILLS_RUNTIME_CATCH_RELEASE_RESET'
 $runtimeIdentityMismatchMutation=Replace-ThriveLensTestSourceOnce -Source $runtimeTest -Old 'elseif ($cycleClusterIdentityFingerprint -cne $clusterIdentityFingerprint)' -New 'elseif ($cycleClusterIdentityFingerprint -ceq $clusterIdentityFingerprint)'
 A ($runtimeIdentityMismatchMutation -cne $runtimeTest -and (Test-ThriveLensSourceParses -Source $runtimeIdentityMismatchMutation) -and -not (Test-ThriveLensRuntimeAdapterContract -Source $runtimeIdentityMismatchMutation)) 'MUTATION_KILLS_RUNTIME_CLUSTER_IDENTITY_MISMATCH_POLARITY'
 $preflightRaw=Get-Content (Join-Path $PSScriptRoot 'preflight.ps1') -Raw;A ($preflightRaw -match 'function Stop-ThriveLensPreflightDistro' -and $preflightRaw -match 'Stop-ThriveLensDistroAndVerify' -and $preflightRaw -match 'Assert-ThriveLensHostPortAbsent') 'PREFLIGHT_EXACT_DISTRO_CLEANUP'
 A ($preflightRaw -match '\$preflightLock=Enter-ThriveLensLifecycleLock' -and $preflightRaw -match 'Assert-ThriveLensWslAbsent' -and $preflightRaw -match 'finally\{if\(\$null -ne \$preflightLock\)') 'PREFLIGHT_LOCKED_ABSENCE_BEFORE_TERMINATE'
 $preflightParsed=Get-ThriveLensParsedSource -Source $preflightRaw;$preflightAdmissionAst=Get-ThriveLensFunctionAst -Ast $preflightParsed.Ast -Name 'Complete-ThriveLensPreflightProbeAndAdmit';$preflightAdmissionDefinition=if($null -ne $preflightAdmissionAst){$preflightAdmissionAst.Extent.Text}else{''}
 A (Test-ThriveLensPreflightWiringContract -Source $preflightRaw) 'PREFLIGHT_TOP_LEVEL_STATUS_WIRING_CONTRACT'
 $preflightStop=$preflightAdmissionDefinition.IndexOf('Stop-ThriveLensPreflightDistro',[StringComparison]::Ordinal)
 $preflightSettle=$preflightAdmissionDefinition.IndexOf('Wait-ThriveLensInterCycleMemorySettle',[StringComparison]::Ordinal)
 $preflightStopped=$preflightAdmissionDefinition.IndexOf('Assert-ThriveLensDistroStopped',$preflightSettle,[StringComparison]::Ordinal)
 $preflightFinalIdentity=$preflightAdmissionDefinition.IndexOf('Assert-ThriveLensWslCleanupIdentity',$preflightStopped,[StringComparison]::Ordinal)
 $preflightFinalHost=$preflightAdmissionDefinition.IndexOf('Assert-ThriveLensHostPortAbsent',$preflightFinalIdentity,[StringComparison]::Ordinal)
 $preflightFinalRam=$preflightAdmissionDefinition.IndexOf('Get-ThriveLensFreeMemoryBytes',$preflightFinalHost,[StringComparison]::Ordinal)
 A ($null -ne $preflightAdmissionAst -and $preflightStop -ge 0 -and $preflightSettle -gt $preflightStop -and
    $preflightStopped -gt $preflightSettle -and $preflightFinalIdentity -gt $preflightStopped -and $preflightFinalHost -gt $preflightFinalIdentity -and $preflightFinalRam -gt $preflightFinalHost -and
    $preflightAdmissionDefinition -match '''RESOURCE_INTER_CYCLE_MEMORY_NOT_SETTLED''\s*\{\s*throw\s+''LOW_FREE_MEMORY_AFTER_WSL_PROBES''' -and
    $preflightAdmissionDefinition -match '''RESOURCE_INTER_CYCLE_MEMORY_MEASUREMENT_UNAVAILABLE''\s*\{\s*throw\s+''MEMORY_MEASUREMENT_UNAVAILABLE_AFTER_WSL_PROBES''' -and
    $preflightRaw -match '\$postProbeCode\s*-cin\s*@\(' -and $preflightRaw -match '\$blockers\.Add\(\$postProbeCode\)' -and $preflightRaw -match 'PREFLIGHT_DISTRO_CLEANUP_FAILED') 'PREFLIGHT_TERMINATE_SETTLE_STOPPED_IDENTITY_HOST_FRESH_RAM_ORDER'
 $preflightSuccess=Invoke-ThriveLensPreflightAdmissionHarness -Definition $preflightAdmissionDefinition -Mode 'SUCCESS';A ($null -eq $preflightSuccess.Code -and ($preflightSuccess.Log -join ',') -ceq 'TERMINATE,SETTLE:1024,DISTRO_STOPPED,IDENTITY,HOST_ABSENT,RAM') 'PREFLIGHT_ADMISSION_EXECUTABLE_SUCCESS_ORDER'
 $preflightSettleLow=Invoke-ThriveLensPreflightAdmissionHarness -Definition $preflightAdmissionDefinition -Mode 'SETTLE_LOW';A ($preflightSettleLow.Code -ceq 'LOW_FREE_MEMORY_AFTER_WSL_PROBES' -and ($preflightSettleLow.Log -join ',') -ceq 'TERMINATE,SETTLE:1024') 'PREFLIGHT_SETTLE_TIMEOUT_EXISTING_LOW_CODE'
 $preflightSettleMeasurement=Invoke-ThriveLensPreflightAdmissionHarness -Definition $preflightAdmissionDefinition -Mode 'SETTLE_MEASUREMENT';A ($preflightSettleMeasurement.Code -ceq 'MEMORY_MEASUREMENT_UNAVAILABLE_AFTER_WSL_PROBES') 'PREFLIGHT_SETTLE_MEASUREMENT_EXISTING_CODE'
 $preflightRelaunched=Invoke-ThriveLensPreflightAdmissionHarness -Definition $preflightAdmissionDefinition -Mode 'RELAUNCHED';A ($preflightRelaunched.Code -ceq 'WSL_DISTRO_STILL_RUNNING' -and ($preflightRelaunched.Log -join ',') -match 'SETTLE:1024,DISTRO_STOPPED$') 'PREFLIGHT_EXTERNAL_RELAUNCH_NEVER_READY'
 $preflightRamLow=Invoke-ThriveLensPreflightAdmissionHarness -Definition $preflightAdmissionDefinition -Mode 'RAM_LOW';A ($preflightRamLow.Code -ceq 'LOW_FREE_MEMORY_AFTER_WSL_PROBES' -and ($preflightRamLow.Log -join ',') -match 'HOST_ABSENT,RAM$') 'PREFLIGHT_FRESH_RAM_LOW_EXISTING_CODE'
 $preflightRamInvalid=Invoke-ThriveLensPreflightAdmissionHarness -Definition $preflightAdmissionDefinition -Mode 'RAM_INVALID';A ($preflightRamInvalid.Code -ceq 'MEMORY_MEASUREMENT_UNAVAILABLE_AFTER_WSL_PROBES') 'PREFLIGHT_FRESH_RAM_INVALID_EXISTING_CODE'
 $preflightHigherThreshold=Invoke-ThriveLensPreflightAdmissionHarness -Definition $preflightAdmissionDefinition -Mode 'SUCCESS' -Threshold 4096;A ($preflightHigherThreshold.Code -ceq 'LOW_FREE_MEMORY_AFTER_WSL_PROBES' -and ($preflightHigherThreshold.Log -join ',') -match 'SETTLE:4096[\s\S]*RAM$') 'PREFLIGHT_CALLER_THRESHOLD_GOVERNS_WAIT_AND_FINAL_SAMPLE'
 $preflightNoStopped=$preflightAdmissionDefinition.Replace('Assert-ThriveLensDistroStopped','$null=$null');$preflightNoStoppedResult=Invoke-ThriveLensPreflightAdmissionHarness -Definition $preflightNoStopped -Mode 'RELAUNCHED';A ($null -eq $preflightNoStoppedResult.Code) 'MUTATION_PROVES_PREFLIGHT_STOPPED_FENCE_REQUIRED'
 $preflightNoFreshRam=$preflightAdmissionDefinition.Replace('try{$memoryValues=@(Get-ThriveLensFreeMemoryBytes)}catch{throw ''MEMORY_MEASUREMENT_UNAVAILABLE_AFTER_WSL_PROBES''}','[object[]]$memoryValues=@([int64]2048)');$preflightNoFreshRamResult=Invoke-ThriveLensPreflightAdmissionHarness -Definition $preflightNoFreshRam -Mode 'RAM_LOW';A ($null -eq $preflightNoFreshRamResult.Code) 'MUTATION_PROVES_PREFLIGHT_FRESH_RAM_REQUIRED'
 $preflightWaitHardcode=$preflightAdmissionDefinition.Replace('Wait-ThriveLensInterCycleMemorySettle -MinimumFreeMemoryBytes $MinimumFreeMemoryBytes','Wait-ThriveLensInterCycleMemorySettle -MinimumFreeMemoryBytes ([int64]1024)');$preflightWaitHardcodeResult=Invoke-ThriveLensPreflightAdmissionHarness -Definition $preflightWaitHardcode -Mode 'SETTLE_LOW' -Threshold 4096;A (($preflightWaitHardcodeResult.Log -join ',') -match 'SETTLE:1024$') 'MUTATION_KILLS_PREFLIGHT_WAIT_THRESHOLD_HARDCODE'
 $preflightFinalHardcode=$preflightAdmissionDefinition.Replace('if($freeMemoryBytes -lt $MinimumFreeMemoryBytes)','if($freeMemoryBytes -lt ([int64]1024))');$preflightFinalHardcodeResult=Invoke-ThriveLensPreflightAdmissionHarness -Definition $preflightFinalHardcode -Mode 'SUCCESS' -Threshold 4096;A ($null -eq $preflightFinalHardcodeResult.Code) 'MUTATION_KILLS_PREFLIGHT_FINAL_THRESHOLD_HARDCODE'
 A ($preflightRaw -match 'catch\s*\{[\s\S]*?\[pscustomobject\]@\{\s*schema_version\s*=\s*1;\s*status\s*=\s*''ERROR'';\s*action\s*=\s*\$Action;\s*codes\s*=\s*@\(''PREFLIGHT_INTERNAL_ERROR''\)\s*\}\s*\|\s*ConvertTo-Json -Compress\s*exit 3' -and
    $preflightRaw -notmatch 'ScriptStackTrace|InvocationInfo|Exception\s*\||Write-Error|Write-Warning') 'PREFLIGHT_TERMINAL_CATCH_SANITIZED_FIXED_SHAPE'
 $preflightRemovedCall=$preflightRaw.Replace('Complete-ThriveLensPreflightProbeAndAdmit -IdentityToken $cleanupIdentityToken -LifecycleLock $preflightLock -MinimumFreeMemoryBytes $minimum','$null=$null');A ((Test-ThriveLensSourceParses -Source $preflightRemovedCall) -and -not (Test-ThriveLensPreflightWiringContract -Source $preflightRemovedCall)) 'MUTATION_KILLS_PREFLIGHT_ADMISSION_CALL_REMOVAL'
 $preflightReadyOnBlocker=$preflightRaw.Replace("status='BLOCKED'","status='READY'");A ((Test-ThriveLensSourceParses -Source $preflightReadyOnBlocker) -and -not (Test-ThriveLensPreflightWiringContract -Source $preflightReadyOnBlocker)) 'MUTATION_KILLS_PREFLIGHT_READY_ON_BLOCKER'
 $preflightBlockedOnCleanup=$preflightRaw.Replace("status='ERROR';action=`$Action;codes=@('PREFLIGHT_DISTRO_CLEANUP_FAILED')","status='BLOCKED';action=`$Action;codes=@('PREFLIGHT_DISTRO_CLEANUP_FAILED')");A ((Test-ThriveLensSourceParses -Source $preflightBlockedOnCleanup) -and -not (Test-ThriveLensPreflightWiringContract -Source $preflightBlockedOnCleanup)) 'MUTATION_KILLS_PREFLIGHT_BLOCKED_ON_CLEANUP'
 $guardStart=$module.IndexOf('function Invoke-ThriveLensGuardedDistro');$guardEnd=$module.IndexOf('function Assert-ThriveLensLifecycleLockOwnership',$guardStart);$guardBody=if($guardStart -ge 0 -and $guardEnd -gt $guardStart){$module.Substring($guardStart,$guardEnd-$guardStart)}else{''}
 A ($guardBody -match 'Assert-ThriveLensLifecycleLockOwnership' -and $guardBody -match 'Assert-ThriveLensWslCleanupIdentity' -and $guardBody -match 'finally' -and $guardBody -match 'Stop-ThriveLensDistroAndVerify' -and $guardBody.IndexOf('Stop-ThriveLensDistroAndVerify') -lt $guardBody.LastIndexOf('throw $failureCode')) 'GUARDED_DISTRO_FAILURE_CONTAINMENT_ORDERED'
 $containmentMarker=$initialize.IndexOf('$containmentVerified=$code -cne ''WSL_GUARDED_COMMAND_CONTAINMENT_FAILED''');$credentialCleanup=$initialize.IndexOf('if($containmentVerified -and $cleanupIdentityReady -and $null -ne $distroPasswordFile)');$nestedContainment=$initialize.IndexOf('$policy=Resolve-ThriveLensCleanupContainmentPolicy',$credentialCleanup);$rollbackGuard=$initialize.IndexOf('if($containmentVerified -and $cleanupIdentityReady -and $null -ne $staging')
 A ($containmentMarker -ge 0 -and $credentialCleanup -gt $containmentMarker -and $nestedContainment -gt $credentialCleanup -and $rollbackGuard -gt $nestedContainment -and $initialize.Substring($nestedContainment,$rollbackGuard-$nestedContainment) -match '\$containmentVerified=\$false') 'INITIALIZE_CONTAINMENT_BEFORE_ROLLBACK'
 foreach($file in @('initialize.ps1','start.ps1','stop.ps1','test_runtime.ps1')){$raw=Get-Content (Join-Path $PSScriptRoot $file)-Raw;A ($raw -notmatch '(?i)wsl\.exe\s+[^\r\n]*Ubuntu(?:\s|$)') ('SHARED_UBUNTU_'+$file)}
 if($fail.Count){[pscustomobject]@{schema_version=1;status='FAIL';codes=@($fail)}|ConvertTo-Json -Compress;exit 1}
 [pscustomobject]@{schema_version=1;status='PASS';assertions=$count}|ConvertTo-Json -Compress
}catch{[pscustomobject]@{schema_version=1;status='ERROR';code='WSL_CONTROL_TEST_INTERNAL_ERROR'}|ConvertTo-Json -Compress;exit 2}
