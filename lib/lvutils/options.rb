require 'lvutils/error'

module LVUtils::Options
  def self.parse(arguments, options)
    # Build keyword hash for argument parsing  
    keywords = {}
    options.each do |opt|
      opt[:names].each { |kw| keywords[kw] = opt } if opt.has_key? :names
    end
    
    # Parse options
    ids = {}
    trailing = false
    while !arguments.empty?
      # Upon encountering an argument which doesn't look like a keyword,
      # or --, everything that follows is a trailing argument
      case arguments.first
        when "--" then trailing = true; arguments.shift
        when /\A[^-]/ then trailing = true; 
      end if !trailing
      
      # Keyword of next option
      kw = trailing ? :trailing : arguments.shift
      raise LVUtils::InvalidOption::new("invalid option #{kw}") unless
        keywords.has_key? kw
      opt = keywords[kw]
      
      # Read as many parameters as the option requires.
      if !trailing
        args = arguments.shift(opt[:handler].arity)
      else
        args = arguments
        arguments.clear
      end
      
      # Validate parameters
      valid = case opt[:validate]
        when Regexp then args.inject(true) { |v, a| v = v && (opt[:validate] =~ a) }
        when Proc then opt[:validate].call(*args)
        else true
      end
      raise LVUtils::InvalidOption::new("Invalid argument #{args.join('  ')} for option #{kw}") unless
        valid
      
      # Handle option
      ids[opt[:id]] = true
      opt[:handler].call(*args)
    end
    
    # Call default handlers for option which weren't specified
    # Note that an option is specified if *some* option with the
    # same id is specified, even if it has different keywords.  
    options.each do |opt|
      next if ids.has_key? opt[:id]
      next unless opt[:enabled].call
      next unless opt.has_key? :default
      opt[:default].call
      ids[opt[:id]] = true
    end

    # Complain about missing mandatory options  
    options.each do |opt|
      next unless opt[:enabled].call
      raise "Missing mandatory option option #{opt[:id]}" unless ids.has_key? opt[:id]
    end
  end
end
