define iis::manage_app_pool (
  $app_pool_name           = $title,
  $enable_32_bit           = false,
  $managed_runtime_version = 'v4.0',
  $managed_pipeline_mode   = 'Integrated',
  $ensure                  = 'present',
  $start_mode              = 'OnDemand',
  $rapid_fail_protection   = true,
  $apppoolmaxprocesses
  ) {
  validate_bool($enable_32_bit)
  validate_re($managed_runtime_version, ['^(v2\.0|v4\.0)$'])
  validate_re($managed_pipeline_mode, ['^(Integrated|Classic)$'])
  validate_re($ensure, '^(present|installed|absent|purged)$', 'ensure must be one of \'present\', \'installed\', \'absent\', \'purged\'')
  validate_re($start_mode, '^(OnDemand|AlwaysRunning)$')
  validate_bool($rapid_fail_protection)

if $apppoolmaxprocesses != undef{
  validate_integer($apppoolmaxprocesses, undef, 0) #0 lets iis detect optimal on numa system, not enforcing max (its an int64)
  $processMaxProcesses = true
}
else{$processMaxProcesses = false}

  if ($ensure in ['present','installed']) {
    exec { "Create-${app_pool_name}" :
      command   => "Import-Module WebAdministration; New-Item \"IIS:\\AppPools\\${app_pool_name}\"",
      provider  => powershell,
      onlyif    => "Import-Module WebAdministration; if((Test-Path \"IIS:\\AppPools\\${app_pool_name}\")) { exit 1 } else { exit 0 }",
      logoutput => true,
    }
    
    exec { "StartMode-${app_pool_name}" :
      command   => "Import-Module WebAdministration; Set-ItemProperty \"IIS:\\AppPools\\${app_pool_name}\" startMode ${start_mode}",
      provider  => powershell,
      onlyif    => "Import-Module WebAdministration; if((Get-ItemProperty \"IIS:\\AppPools\\${app_pool_name}\" startMode).CompareTo('${start_mode}') -eq 0) { exit 1 } else { exit 0 }",
      require   => Exec["Create-${app_pool_name}"],
      logoutput => true,
    }

    exec { "RapidFailProtection-${app_pool_name}" :
      command   => "Import-Module WebAdministration; Set-ItemProperty \"IIS:\\AppPools\\${app_pool_name}\" failure.rapidFailProtection ${rapid_fail_protection}",
      provider  => powershell,
      onlyif    => "Import-Module WebAdministration; if((Get-ItemProperty \"IIS:\\AppPools\\${app_pool_name}\" failure.rapidFailProtection).Value -eq [System.Convert]::ToBoolean('${rapid_fail_protection}')) { exit 1 } else { exit 0 }",
      require   => Exec["Create-${app_pool_name}"],
      logoutput => true,
    }
    
    exec { "Framework-${app_pool_name}" :
      command   => "Import-Module WebAdministration; Set-ItemProperty \"IIS:\\AppPools\\${app_pool_name}\" managedRuntimeVersion ${managed_runtime_version}",
      provider  => powershell,
      onlyif    => "Import-Module WebAdministration; if((Get-ItemProperty \"IIS:\\AppPools\\${app_pool_name}\" managedRuntimeVersion).Value.CompareTo('${managed_runtime_version}') -eq 0) { exit 1 } else { exit 0 }",
      require   => Exec["Create-${app_pool_name}"],
      logoutput => true,
    }

    exec { "32bit-${app_pool_name}" :
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

    exec { "ManagedPipelineMode-${app_pool_name}" :
      command   => "Import-Module WebAdministration; Set-ItemProperty \"IIS:\\AppPools\\${app_pool_name}\" managedPipelineMode ${managed_pipeline_mode_value}",
      provider  => powershell,
      onlyif    => "Import-Module WebAdministration; if((Get-ItemProperty \"IIS:\\AppPools\\${app_pool_name}\" managedPipelineMode).CompareTo('${managed_pipeline_mode}') -eq 0) { exit 1 } else { exit 0 }",
      require   => Exec["Create-${app_pool_name}"],
      logoutput => true,
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

    }
 else {
    exec { "Delete-${app_pool_name}":
      command   => "Import-Module WebAdministration; Remove-Item \"IIS:\\AppPools\\${app_pool_name}\" -Recurse",
      provider  => powershell,
      onlyif    => "Import-Module WebAdministration; if(!(Test-Path \"IIS:\\AppPools\\${app_pool_name}\")) { exit 1 } else { exit 0 }",
      logoutput => true,
    }
  }
}
