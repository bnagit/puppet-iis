# apppool identity - caller MUST specify $apppoolusername $apppoolpassword if using "SpecificUser" identity type
define iis::manage_app_pool (
  $app_pool_name           = $title,
  $enable_32_bit           = false,
  $managed_runtime_version = 'v4.0',
  $managed_pipeline_mode   = 'Integrated',
  $ensure                  = 'present',
  $start_mode              = 'OnDemand',
  $rapid_fail_protection   = true,
  $apppoolidentitytype,
  $apppoolusername,
  $apppooluserpw) {
  validate_bool($enable_32_bit)
  validate_re($managed_runtime_version, ['^(v2\.0|v4\.0)$'])
  validate_re($managed_pipeline_mode, ['^(Integrated|Classic)$'])
  validate_re($ensure, '^(present|installed|absent|purged)$', 'ensure must be one of \'present\', \'installed\', \'absent\', \'purged\''
  )
  validate_re($start_mode, '^(OnDemand|AlwaysRunning)$')
  validate_bool($rapid_fail_protection)

  # keeping new stuff optional for backwards compatibility
  if $apppoolidentitytype != undef {
    validate_re($apppoolidentitytype, ['^(0|1|2|3|4|LocalSystem|LocalService|NetworkService|SpecificUser|ApplicationPoolIdentity)$'
      ], 'identitytype must be one of \'0\', \'1\',\'2\',\'3\',\'4\',\'LocalSystem\',\'LocalService\',\'NetworkService\',\'SpecificUser\',\'ApplicationPoolIdentity\''
      )

    if ($apppoolidentitytype in [
      '3',
      'SpecificUser']) {
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

  if ($ensure in [
    'present',
    'installed']) {
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

  } else {
    exec { "Delete-${app_pool_name}":
      command   => "Import-Module WebAdministration; Remove-Item \"IIS:\\AppPools\\${app_pool_name}\" -Recurse",
      provider  => powershell,
      onlyif    => "Import-Module WebAdministration; if(!(Test-Path \"IIS:\\AppPools\\${app_pool_name}\")) { exit 1 } else { exit 0 }",
      logoutput => true,
    }

  }
}
