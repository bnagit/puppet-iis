#all of the things
define iis::manage_app_pool (
  $app_pool_name           = $title,
  $enable_32_bit           = false,
  $managed_runtime_version = 'v4.0',
  $managed_pipeline_mode   = 'Integrated',
  $ensure                  = 'present',
  $start_mode              = 'OnDemand',
  $rapid_fail_protection   = true,
  $apppoolidentitytype = undef,
  $apppoolusername = undef,
  $apppooluserpw = undef,
  $apppoolidletimeoutminutes = undef,
  $apppoolmaxprocesses = undef,
  $apppoolmaxqueuelength = undef,
  $apppoolrecycleperiodicminutes = undef,
  $apppoolrecyclelogging = undef,
  $apppoolrecycleschedule = undef) {
  validate_bool($enable_32_bit)
  validate_re($managed_runtime_version, ['^(v2\.0|v4\.0)$'])
  validate_re($managed_pipeline_mode, ['^(Integrated|Classic)$'])
  validate_re($ensure, '^(present|installed|absent|purged)$', 'ensure must be one of \'present\', \'installed\', \'absent\', \'purged\'')
  validate_re($start_mode, '^(OnDemand|AlwaysRunning)$')
  validate_bool($rapid_fail_protection)

  # keeping new stuff optional for backwards compatibility
  if $apppoolidentitytype != undef {

    validate_re($apppoolidentitytype, ['^(0|1|2|3|4|LocalSystem|LocalService|NetworkService|SpecificUser|ApplicationPoolIdentity)$'], 'identitytype must be one of \'0\', \'1\',\'2\',\'3\',\'4\',\'LocalSystem\',\'LocalService\',\'NetworkService\',\'SpecificUser\',\'ApplicationPoolIdentity\'')

    if ($apppoolidentitytype in ['3','SpecificUser']) {
      if ($apppoolusername == undef) or (empty($apppoolusername)) {
        fail('attempt set app pool identity to SpecificUser null or zero length $apppoolusername param')
      }

      if ($apppooluserpw == undef) or (empty($apppooluserpw)) {
        fail('attempt set app pool identity to SpecificUser null or zero length $apppooluserpw param')
      }
    }

    case $apppoolidentitytype {
      '0', 'LocalSystem'             : {
        $identitystring = 'LocalSystem'
        $identityEnum   = '0'
      }
      '1', 'LocalService'            : {
        $identitystring = 'LocalService'
        $identityEnum   = '1'
      }
      '2', 'NetworkService'          : {
        $identitystring = 'NetworkService'
        $identityEnum   = '2'
      }
      '3', 'SpecificUser'            : {
        $identitystring = 'SpecificUser'
        $identityEnum   = '3'
      }
      '4', 'ApplicationPoolIdentity' : {
        $identitystring = 'ApplicationPoolIdentity'
        $identityEnum   = '4'
      }
      default : {
        $identitystring = 'ApplicationPoolIdentity'
        $identityEnum   = '4'
      }
    }

    $processAppPoolIdentity = true

  }
  else
  {$processAppPoolIdentity = false}

if $apppoolidletimeoutminutes != undef {
  validate_integer($apppoolidletimeoutminutes, 43200, 0) #30 days (43200 min) is max value for this in iis, 0 disables
  $processAppPoolIdleTimeout = true
  $idleTimeoutTicks = $apppoolidletimeoutminutes * 600000000
}
else{$processAppPoolIdleTimeout = false}

if $apppoolmaxprocesses != undef{
  validate_integer($apppoolmaxprocesses, undef, 0) #0 lets iis detect optimal on numa system, not enforcing max (its an int64)
  $processMaxProcesses = true
}
else{$processMaxProcesses = false}

if $apppoolmaxqueuelength != undef{
  validate_integer($apppoolmaxqueuelength, 65535, 10) #app pool max queue length must be set 10 >= n <= 65535
  $processMaxQueueLength = true
}
else{$processMaxQueueLength = false}

if $apppoolrecycleperiodicminutes != undef {
 if (!empty($apppoolrecycleperiodicminutes)) {
    validate_integer($apppoolrecycleperiodicminutes, 15372286728, 0) # powershell $([int64]::MaxValue) / 600000000, we're not dealing with negative
    $periodicticks = $apppoolrecycleperiodicminutes * 600000000
    $processperiodictimes = true
  }
  else
  {
    $processperiodictimes = false
  }
}
else{$processperiodictimes = false}

if $apppoolrecyclelogging != undef {
  if(!empty($apppoolrecyclelogging))
  {
    $apppoolrecyclelogging.each |String $loggingoption| {
validate_re($loggingoption, '^(Time|Requests|Schedule|Memory|IsapiUnhealthy|OnDemand|ConfigChange|PrivateMemory)$', "bad ${$loggingoption} - [\$apppoolrecyclelogging] values must be one of \'Time\',\'Requests\',\'Schedule\',\'Memory\',\'IsapiUnhealthy\',\'OnDemand\',\'ConfigChange\',\'PrivateMemory\'")
    }

    $loggingstring    = join($apppoolrecyclelogging, ',') # Time,Requests
    $fixedloggingstring      = "\"${loggingstring}\"" # @"Time,Requests" as literal - we put this into powershell array constructor in
                                                      # execs

    $processAppPoolRecycleLogging = true
  }
  else{
$fixedloggingstring = ''
$processAppPoolRecycleLogging = true #caller provided empty arry for multi-value enum, wants to clear it
}
}
else
{$processAppPoolRecycleLogging = false}

  if $apppoolrecycleschedule != undef {
    if (!empty($apppoolrecycleschedule)) {
    $apppoolrecycleschedule.each |String $time| {
      validate_re($time, '\b\d{2}:\d{2}:\d{2}\b', "${time} bad - time format hh:mm:ss in array")
    }
    $restarttimesstring    = join($apppoolrecycleschedule, ',') # 01:00:00,02:00:00
    $tempstr               = regsubst($restarttimesstring, '([,]+)', "\"\\1\"", 'G') # 01:00:00"."02:00:00
    $fixedtimesstring      = "\"${tempstr}\"" # @"01:00:00","02:00:00" as literal - we put this into powershell array constructor in
                                              # execs
    $processscheduledtimes = true
  }
  else
  {$processscheduledtimes = true} #caller specified empty array - they want to clear scheduled recycles
  }
  else
  {$processscheduledtimes = false}

  if ($ensure in ['present','installed']) {
    exec { "Create-${app_pool_name}":
      command   => "Import-Module WebAdministration; New-Item \"IIS:\\AppPools\\${app_pool_name}\"",
      provider  => powershell,
      onlyif    => "Import-Module WebAdministration; if((Test-Path \"IIS:\\AppPools\\${app_pool_name}\")) { exit 1 } else { exit 0 }",
      logoutput => true,
    }

    exec { "StartMode-${app_pool_name}":
      command   => "Import-Module WebAdministration; Set-ItemProperty \"IIS:\\AppPools\\${app_pool_name}\" startMode ${start_mode}",
      provider  => powershell,
      onlyif    => "Import-Module WebAdministration; if((Get-ItemProperty \"IIS:\\AppPools\\${app_pool_name}\" startMode).CompareTo('${start_mode}') -eq 0) { exit 1 } else { exit 0 }",
      require   => Exec["Create-${app_pool_name}"],
      logoutput => true,
    }

    exec { "RapidFailProtection-${app_pool_name}":
      command   => "Import-Module WebAdministration; Set-ItemProperty \"IIS:\\AppPools\\${app_pool_name}\" failure.rapidFailProtection ${rapid_fail_protection}",
      provider  => powershell,
      onlyif    => "Import-Module WebAdministration; if((Get-ItemProperty \"IIS:\\AppPools\\${app_pool_name}\" failure.rapidFailProtection).Value -eq [System.Convert]::ToBoolean('${rapid_fail_protection}')) { exit 1 } else { exit 0 }",
      require   => Exec["Create-${app_pool_name}"],
      logoutput => true,
    }

    exec { "Framework-${app_pool_name}":
      command   => "Import-Module WebAdministration; Set-ItemProperty \"IIS:\\AppPools\\${app_pool_name}\" managedRuntimeVersion ${managed_runtime_version}",
      provider  => powershell,
      onlyif    => "Import-Module WebAdministration; if((Get-ItemProperty \"IIS:\\AppPools\\${app_pool_name}\" managedRuntimeVersion).Value.CompareTo('${managed_runtime_version}') -eq 0) { exit 1 } else { exit 0 }",
      require   => Exec["Create-${app_pool_name}"],
      logoutput => true,
    }

    exec { "32bit-${app_pool_name}":
      command   => "Import-Module WebAdministration; Set-ItemProperty \"IIS:\\AppPools\\${app_pool_name}\" enable32BitAppOnWin64 ${enable_32_bit}",
      provider  => powershell,
      onlyif    => "Import-Module WebAdministration; if((Get-ItemProperty \"IIS:\\AppPools\\${app_pool_name}\" enable32BitAppOnWin64).Value -eq [System.Convert]::ToBoolean('${enable_32_bit}')) { exit 1 } else { exit 0 }",
      require   => Exec["Create-${app_pool_name}"],
      logoutput => true,
    }

    $managed_pipeline_mode_value = downcase($managed_pipeline_mode) ? {
      'integrated' => 0,
      'classic'    => 1,
      default      => 0,
    }

    exec { "ManagedPipelineMode-${app_pool_name}":
      command   => "Import-Module WebAdministration; Set-ItemProperty \"IIS:\\AppPools\\${app_pool_name}\" managedPipelineMode ${managed_pipeline_mode_value}",
      provider  => powershell,
      onlyif    => "Import-Module WebAdministration; if((Get-ItemProperty \"IIS:\\AppPools\\${app_pool_name}\" managedPipelineMode).CompareTo('${managed_pipeline_mode}') -eq 0) { exit 1 } else { exit 0 }",
      require   => Exec["Create-${app_pool_name}"],
      logoutput => true,
    }

    if ($processAppPoolIdentity) {
      if ($identitystring == 'SpecificUser') {
        exec { "app pool identitytype -  ${app_pool_name} - SPECIFICUSER - ${apppoolusername}":
          command   => "[void] [System.Reflection.Assembly]::LoadWithPartialName(\"Microsoft.Web.Administration\");\$iis = New-Object Microsoft.Web.Administration.ServerManager;iis:;\$pool = get-item IIS:\\AppPools\\${app_pool_name};\$pool.processModel.username = \"${apppoolusername}\";\$pool.processModel.password = \"${apppooluserpw}\";\$pool.processModel.identityType = ${identityEnum};\$pool | set-item;",
          provider  => powershell,
          unless    => "[void] [System.Reflection.Assembly]::LoadWithPartialName(\"Microsoft.Web.Administration\");\$iis = New-Object Microsoft.Web.Administration.ServerManager;iis:;\$pool = get-item IIS:\\AppPools\\${app_pool_name};if(\$pool.processModel.identityType -ne \"${identitystring}\"){exit 1;}if(\$pool.processModel.userName -ne ${apppoolusername}){exit 1;}if(\$pool.processModel.password -ne ${apppooluserpw}){exit 1;}exit 0;",
          require   => Exec["Create-${app_pool_name}"],
          logoutput => true,
        }
      } else {
        exec { "app pool identitytype -  ${app_pool_name} - ${identitystring}":
          command   => "[void] [System.Reflection.Assembly]::LoadWithPartialName(\"Microsoft.Web.Administration\");\$iis = New-Object Microsoft.Web.Administration.ServerManager;iis:;\$pool = get-item IIS:\\AppPools\\${app_pool_name};\$pool.processModel.identityType = ${identityEnum};\$pool | set-item;",
          provider  => powershell,
          unless    => "[void] [System.Reflection.Assembly]::LoadWithPartialName(\"Microsoft.Web.Administration\");\$iis = New-Object Microsoft.Web.Administration.ServerManager;iis:;\$pool = get-item IIS:\\AppPools\\${app_pool_name};if(\$pool.processModel.identityType -eq \"${identitystring}\"){exit 0;}else{exit 1;}",
          require   => Exec["Create-${app_pool_name}"],
          logoutput => true,
        }
      }
    }

      if($processAppPoolIdleTimeout)
  {
        exec { "App Pool Idle Timeout - ${app_pool_name}":
        command   => "Import-Module WebAdministration;\$appPoolPath = (\"IIS:\\AppPools\\\" + \"${app_pool_name}\");[TimeSpan]\$ts = ${idleTimeoutTicks};Set-ItemProperty \$appPoolPath -name processModel -value @{idletimeout=\$ts}",
        provider  => powershell,
        unless    => "Import-Module WebAdministration;\$appPoolPath = (\"IIS:\\AppPools\\\" + \"${app_pool_name}\");[TimeSpan]\$ts = ${idleTimeoutTicks};if((get-ItemProperty \$appPoolPath -name processModel.idletimeout.value) -ne \$ts){exit 1;}exit 0;",
        require   => Exec["Create-${app_pool_name}"],
        logoutput => true,
      }
  }

      if($processMaxProcesses)
  {
        exec { "App Pool Max Processes - ${app_pool_name}":
        command   => "Import-Module WebAdministration;\$appPoolPath = (\"IIS:\\AppPools\\\" + \"${app_pool_name}\");Set-ItemProperty \$appPoolPath -name processModel -value @{maxProcesses=${apppoolmaxprocesses}}",
        provider  => powershell,
        unless    => "Import-Module WebAdministration;\$appPoolPath = (\"IIS:\\AppPools\\\" + \"${app_pool_name}\");if((get-ItemProperty \$appPoolPath -name processModel.maxprocesses.value) -ne ${apppoolmaxprocesses}){exit 1;}exit 0;",
        require   => Exec["Create-${app_pool_name}"],
        logoutput => true,
      }
  }

      if($processMaxQueueLength)
  {
        exec { "App Pool Max Queue Length - ${app_pool_name}":
        command   => "Import-Module WebAdministration;\$appPoolPath = (\"IIS:\\AppPools\\\" + \"${app_pool_name}\");Set-ItemProperty \$appPoolPath queueLength ${apppoolmaxqueuelength};",
        provider  => powershell,
        unless    => "Import-Module WebAdministration;\$appPoolPath = (\"IIS:\\AppPools\\\" + \"${app_pool_name}\");if((get-ItemProperty \$appPoolPath).queuelength -ne ${apppoolmaxqueuelength}){exit 1;}exit 0;",
        require   => Exec["Create-${app_pool_name}"],
        logoutput => true,
      }
  }

          if($processperiodictimes)
    {
        exec { "App Pool Recycle Periodic - ${app_pool_name} - ${apppoolrecycleperiodicminutes}":
        command   => "\$appPoolName = \"${app_pool_name}\";[TimeSpan] \$ts = ${periodicticks};Import-Module WebAdministration;\$appPoolPath = (\"IIS:\\AppPools\\\" + \$appPoolName);Get-ItemProperty \$appPoolPath -Name recycling.periodicRestart.time;Set-ItemProperty \$appPoolPath -Name recycling.periodicRestart.time -value \$ts;",
        provider  => powershell,
        unless    => "\$appPoolName = \"${app_pool_name}\";[TimeSpan] \$ts = ${periodicticks};Import-Module WebAdministration;\$appPoolPath = (\"IIS:\\AppPools\\\" + \$appPoolName);if((Get-ItemProperty \$appPoolPath -Name recycling.periodicRestart.time.value) -ne \$ts.Ticks){exit 1;}exit 0;",
        require   => Exec["Create-${app_pool_name}"],
        logoutput => true,
      }
    }

          if($processAppPoolRecycleLogging)
  {

        if((empty($fixedloggingstring))){
        exec { "Clear App Pool Logging - ${app_pool_name}":
        command   => "\$appPoolName = \"${app_pool_name}\";Import-Module WebAdministration;\$appPoolPath = (\"IIS:\\AppPools\\\" + \$appPoolName);Set-ItemProperty \$appPoolPath -name recycling -value @{\"\"};",
        provider  => powershell,
        unless    => "\$appPoolName = \"${app_pool_name}\";Import-Module WebAdministration;\$appPoolPath = (\"IIS:\\AppPools\\\" + \$appPoolName);if((Get-ItemProperty \$appPoolPath -Name Recycling.LogEventOnRecycle).value -eq 0){exit 0;}else{exit 1;}",
        require   => Exec["Create-${app_pool_name}"],
        logoutput => true,
      }
        }
        else
        {
        exec { "App Pool Logging - ${app_pool_name}":
        command   => "\$appPoolName = \"${app_pool_name}\";Import-Module WebAdministration;\$appPoolPath = (\"IIS:\\AppPools\\\" + \$appPoolName);Set-ItemProperty \$appPoolPath -name recycling -value @{logEventOnRecycle=${fixedloggingstring}};",
        provider  => powershell,
        unless    => "\$appPoolName = \"${app_pool_name}\";Import-Module WebAdministration;\$appPoolPath = (\"IIS:\\AppPools\\\" + \$appPoolName);[string[]]\$LoggingOptions = @(${fixedloggingstring});[Collections.Generic.List[String]]\$collectionAsList = @();if((Get-ItemProperty \$appPoolPath -Name Recycling.LogEventOnRecycle).value -eq 0){exit 1;}[string[]]\$enumsplit = (Get-ItemProperty \$appPoolPath -Name Recycling.LogEventOnRecycle).Split(',');if(\$LoggingOptions.Length -ne \$enumsplit.Length){exit 1;}foreach(\$s in \$LoggingOptions){if(\$enumsplit.Contains(\$s) -eq \$false){exit 1;}}exit 0;",
        require   => Exec["Create-${app_pool_name}"],
        logoutput => true,
      }
        }
  }

      if($processscheduledtimes)
    {
            if(empty($apppoolrecycleschedule))
      {
        #clear scheduled app pool recycles
        exec { "CLEAR App Pool Recycle Schedule - ${app_pool_name} - ${fixedtimesstring}":
        command   => "[string]\$ApplicationPoolName = \"${app_pool_name}\";Import-Module WebAdministration;Write-Output \"removing scheduled recycles\";Clear-ItemProperty IIS:\\AppPools\\\$ApplicationPoolName -Name Recycling.periodicRestart.schedule;",
        provider  => powershell,
        unless    => "[string]\$ApplicationPoolName = \"${app_pool_name}\";Import-Module WebAdministration;if((Get-ItemProperty IIS:\\AppPools\\\$ApplicationPoolName -Name Recycling.periodicRestart.schedule.collection).Length -eq \$null){exit 0;}else{exit 1;}",
        require   => Exec["Create-${app_pool_name}"],
        logoutput => true,
}
      }
      else
      {
      exec { "App Pool Recycle Schedule - ${app_pool_name} - ${fixedtimesstring}":
        command   => "[string]\$ApplicationPoolName = \"${app_pool_name}\";[string[]]\$RestartTimes = @(${fixedtimesstring});Import-Module WebAdministration;Clear-ItemProperty IIS:\\AppPools\\\$ApplicationPoolName -Name Recycling.periodicRestart.schedule;foreach (\$restartTime in \$RestartTimes){Write-Output \"Adding recycle at \$restartTime\";New-ItemProperty -Path \"IIS:\\AppPools\\\$ApplicationPoolName\" -Name Recycling.periodicRestart.schedule -Value @{value=\$restartTime};}",
        provider  => powershell,
        unless    => "[string]\$ApplicationPoolName = \"${app_pool_name}\";[string[]]\$RestartTimes = @(${fixedtimesstring});Import-Module WebAdministration;[Collections.Generic.List[String]]\$collectionAsList = @();for(\$i=0; \$i -lt (Get-ItemProperty IIS:\\AppPools\\\$ApplicationPoolName -Name Recycling.periodicRestart.schedule.collection).Length; \$i++){\$collectionAsList.Add((Get-ItemProperty IIS:\\AppPools\\\$ApplicationPoolName -Name Recycling.periodicRestart.schedule.collection)[\$i].value.ToString());}if(\$collectionAsList.Count -ne \$RestartTimes.Length){exit 1;}foreach (\$restartTime in \$RestartTimes) {if(!\$collectionAsList.Contains(\$restartTime)){exit 1;}}exit 0;",
        require   => Exec["Create-${app_pool_name}"],
        logoutput => true,
      }
}
    }

  } else {
    exec { "Delete-${app_pool_name}":
      command   => "Import-Module WebAdministration; Remove-Item \"IIS:\\AppPools\\${app_pool_name}\" -Recurse",
      provider  => powershell,
      onlyif    => "Import-Module WebAdministration; if(!(Test-Path \"IIS:\\AppPools\\${app_pool_name}\")) { exit 1 } else { exit 0 }",
      logoutput => true,
    }

  }
}
