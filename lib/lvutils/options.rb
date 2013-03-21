require 'lvutils/error'

module LVUtils::Options
  def self.help(io, options)
    # Collect modes
    modes = []
    options.each do |opt|
      modes << opt[:mode] unless modes.include? opt[:mode]
    end

    # Show syntax overview, one line per mode
    io <<  "OVERVIEW\n"
    modes.each do |mode|
      # Indent & program name
      io << "    "
      io << File::basename($0)
      
      # List options
      options.each do |opt|
        # Skip dummy options
        next unless opt[:mode] == mode
        next unless opt.has_key? :names
        next unless opt.has_key? :handler
        
        # Construct list of option names and parameters
        names = opt[:names].select { |n| n != :trailing}
        parameters = opt[:handler].parameters.inject([]) { |l,p| l << p[1].to_s.upcase; l << "..." if p[0] == :rest; l}
        optional = opt.has_key? :default

	# Output
	io << " "        
        io << "[--] " if names.empty?
        io << "[" if optional
        io << names.join(",")
        io << " " unless names.empty?
        io << parameters.join(", ")
        io << "]" if optional
      end
      io << "\n"
    end
    io << "\n"
    
    # Show detailed description for each option
    io << "OPTION DESCRIPTION\n"
    options.each do |opt|
      # Skip dummy options
      next unless opt.has_key? :names
      next unless opt.has_key? :handler
      
      # Construct list of option names and parameters
      names = opt[:names].select { |n| n != :trailing}
      parameters = opt[:handler].parameters.inject([]) { |l,p| l << p[1].to_s.upcase; l << "..." if p[0] == :rest; l}

      # Output
      io << "    "
      io << names.join(",")
      io << " " unless parameters.empty?
      io << parameters.join(", ")
      io << "\n"
      io << "      "
      io << opt[:desc]
      io << "\n\n"
    end
  end

  def self.parse(arguments, options)
    # Build keyword hash for argument parsing  
    keywords = {}
    options.each do |opt|
      opt[:names].each { |kw| keywords[kw] = opt } if opt.has_key? :names
    end
    
    # Parse options
    mode = nil
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
      raise LVUtils::InvalidOption::new("unknown option #{kw}") unless
        keywords.has_key? kw
      opt = keywords[kw]
      raise LVUtils::InvalidOption::new("invalid option #{kw}") unless
        mode.nil? || (mode == opt[:mode])
      
      # Read as many parameters as the option requires.
      if !trailing
        args = arguments.shift(opt[:handler].arity)
      else
        args, arguments = arguments, []
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
      mode = mode || opt[:mode] if opt.has_key? :mode
    end
    
    # Call default handlers for option which weren't specified
    # Note that an option is specified if *some* option with the
    # same id is specified, even if it has different keywords.  
    options.each do |opt|
      next if ids.has_key? opt[:id]
      next unless mode.nil? || (opt[:mode] == mode)
      next unless opt.has_key? :default
      ids[opt[:id]] = true
      opt[:default].call
      mode = mode || opt[:mode] if opt.has_key? :mode
    end

    # Complain about missing mandatory options  
    options.each do |opt|
      next unless mode.nil? || (opt[:mode] == mode)
      raise LVUtils::InvalidOption::new("Missing mandatory option option #{opt[:id]}") unless ids.has_key? opt[:id]
    end
  end
end
