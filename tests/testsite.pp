#moved out of init.pp to prevent accidental referencing of iis class creating websites and bindings in a location where there may very well be code
#c:\inetpub\wwwroot\test a bad place to serve a sample site from
 iis::manage_app_pool {'www.internalapi.co.uk':
    enable_32_bit           => true,
    managed_runtime_version => 'v4.0',
  }

  iis::manage_site {'www.internalapi.co.uk':
    site_path   => 'C:\inetpub\wwwroot\test',
    port        => '80',
    ip_address  => '*',
    host_header => 'www.internalapi.co.uk',
    app_pool    => 'www.internalapi.co.uk'
  }

  iis::manage_virtual_application {'reviews':
    site_name => 'www.internalapi.co.uk',
    site_path => 'C:\inetpub\wwwroot\test',
    app_pool  => 'www.internalapi.co.uk'
  }
