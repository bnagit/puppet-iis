module Puppet::Parser::Functions
  newfunction(:is_array_in_array, :type => :rvalue, :doc => "check values in args[0] in args[1]") do |args|
    raise(Puppet::ParseError, "is_bool(): Wrong number of arguments " + "given (#{args.size} for 2)") if args.size != 2
    isvalid = true
    inputar = args[0]
    validatear = args[1]
    inputar.each do |item|
      if !validatear.include? item
        isvalid = false
      end
    end
    return isvalid
  end
