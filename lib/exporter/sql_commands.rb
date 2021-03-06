module Myreplicator
  module SqlCommands
    
    def self.mysqldump *args
      options = args.extract_options!
      options.reverse_merge! :flags => []
      db = options[:db]

      flags = ""

      self.dump_flags.each_pair do |flag, value|
        if options[:flags].include? flag
          flags += " --#{flag} "
        elsif value
          flags += " --#{flag} "
        end
      end

      # Database host when ssh'ed into the db server
      db_host = "127.0.0.1" 

      if !ssh_configs(db)["ssh_db_host"].blank? 
        db_host =  ssh_configs(db)["ssh_db_host"]
      elsif !db_configs(db)["host"].blank?
        db_host = db_configs(db)["host"]
      end

      cmd = Myreplicator.mysqldump
      cmd += "#{flags} -u#{db_configs(db)["username"]} -p#{db_configs(db)["password"]} "
      Kernel.p "==== db_configs(db)['unuse_host_and_port'].blank? ====="
      Kernel.p db_configs(db)
      Kernel.p db_configs(db)["unuse_host_and_port"].blank?
      cmd += "-h#{db_host} " if db_configs(db)["unuse_host_and_port"].blank?
      cmd += " -P#{db_configs(db)["port"]} " if (db_configs(db)["port"] && db_configs(db)["unuse_host_and_port"].blank?)
      cmd += " #{db} "
      cmd += " #{options[:table_name]} "
      cmd += "--result-file=#{options[:filepath]} "

      # cmd += "--tab=#{options[:filepath]} "
      # cmd += "--fields-enclosed-by=\'\"\' "
      # cmd += "--fields-escaped-by=\'\\\\\' "
      puts cmd  
      return cmd
    end

    ##
    # Db configs for active record connection
    ## 

    def self.db_configs db
      ActiveRecord::Base.configurations[db]
    end

    ##
    # Configs needed for SSH connection to source server
    ##

    def self.ssh_configs db
      Myreplicator.configs[db]
    end

    ##
    # Default dump flags
    ## 
    def self.dump_flags
      {"add-locks" => false,
        "compact" => false,
        "lock-tables" => false,
        "no-create-db" => true,
        "no-data" => false,
        "quick" => true,
        "skip-add-drop-table" => false,
        "create-options" => false,
        "single-transaction" => false
      }
    end

    ##
    # Mysql exports using -e flag
    ## 

    def self.mysql_export *args
      options = args.extract_options!
      options.reverse_merge! :flags => []
      db = options[:db]
      
      # Database host when ssh'ed into the db server
      
      db_host = "127.0.0.1" 
      
      if !ssh_configs(db)["ssh_db_host"].blank? 
        db_host =  ssh_configs(db)["ssh_db_host"]
      elsif !db_configs(db)["host"].blank?
        db_host = db_configs(db)["host"]
      end
      
      flags = ""

      self.mysql_flags.each_pair do |flag, value|
        if options[:flags].include? flag
          flags += " --#{flag} "
        elsif value
          flags += " --#{flag} "
        end
      end

      cmd = Myreplicator.mysql
      cmd += "#{flags} -u#{db_configs(db)["username"]} -p#{db_configs(db)["password"]} " 

      cmd += "-h#{db_host} " 
      cmd += db_configs(db)["port"].blank? ? "-P3306 " : "-P#{db_configs(db)["port"]} "
      cmd += "--execute=\"#{options[:sql]}\" "
      cmd += " > #{options[:filepath]} "
      
      puts cmd
      return cmd
    end
    
    ##
    # exp: 
    # SELECT 
    # customer_id,firstname,REPLACE(UPPER(`lastname`), 'NULL', 'ABC'),email,..,REPLACE(`modified_date`, '0000-00-00','1900-01-01'),..
    # FROM king.customer WHERE customer_id in ( 261085,348081,477336 );
    ##
    
    def self.get_columns * args
      options = args.extract_options!
      #Kernel.p "===== GET COLUMNS OPTIONS ====="
      #Kernel.p options
      #
      exp = Myreplicator::Export.find(options[:export_id])
      #
      mysql_schema = Myreplicator::Loader.mysql_table_definition(options)
      mysql_schema_simple_form = Myreplicator::MysqlExporter.get_mysql_schema_rows mysql_schema
      columns = Myreplicator::VerticaLoader.get_mysql_inserted_columns mysql_schema_simple_form
      #Kernel.p "===== table's columns====="
      #Kernel.p columns
      if !exp.removing_special_chars.blank?
        json = JSON.parse(exp.removing_special_chars)
      else
        json = {}
      end
      #Kernel.p exp.removing_special_chars
      #Kernel.p json
      result = []
      columns.each do |column|
        if !json[column].blank?
          puts json[column]
          replaces = json[column]
          sql = ""
          replaces.each do |k,v|
            if sql.blank?
              sql = "REPLACE(\\`#{column}\\`, '#{k}', '#{v}')"
            else
              sql = "REPLACE(#{sql}, '#{k}', '#{v}')"
            end
            sql.gsub!("back_slash","\\\\\\\\\\")
            #puts sql
          end
          result << sql
        else
          result << "\\`#{column}\\`"
        end
      end
      Kernel.p result
      return result
    end

    ##
    # Mysql export data into outfile option
    # Provided for tables that need special delimiters
    ##
    
    def self.get_outfile_sql *args 
      options = args.extract_options!
      #Kernel.p "===== SELECT * INTO OUTFILE OPTIONS====="
      #Kernel.p options
      columns = get_columns options
      sql = "SELECT #{columns.join(',')} INTO OUTFILE '#{options[:filepath]}' "
      #sql = "SELECT * INTO OUTFILE '#{options[:filepath]}' " 
      
      if options[:enclosed_by].blank?
        sql += " FIELDS TERMINATED BY '\\0' ESCAPED BY '' LINES TERMINATED BY ';~~;\n'"
      else
        sql += " FIELDS TERMINATED BY '\\0' ESCAPED BY '' ENCLOSED BY '#{options[:enclosed_by]}'  LINES TERMINATED BY ';~~;\n'"
      end
      
      sql += "FROM #{options[:db]}.#{options[:table]} "

      if options[:export_type]=="incremental" && !options[:incremental_col].blank? && !options[:incremental_val].blank?
        if options[:incremental_col_type] == "datetime"
          if options[:incremental_val] == "0"
            options[:incremental_val] = "1900-01-01 00:00:00"
          end
          sql += "WHERE #{options[:incremental_col]} >= '#{(DateTime.parse(options[:incremental_val]) -1.hour).to_s(:db)}'" #buffer 1 hour
        elsif options[:incremental_col_type] == "int"
          if options[:incremental_val].blank?
            options[:incremental_val] = "0"
          end
          sql += "WHERE #{options[:incremental_col]} >= #{options[:incremental_val].to_i - 10000}" #buffer 10000 
        end
      end
      Kernel.p sql
      return sql
    end

    ##
    # Export using outfile
    # \\0 delimited
    # terminated by newline 
    # Location of the output file needs to have 777 perms
    ##
    def self.mysql_export_outfile *args
      Kernel.p "===== mysql_export_outfile OPTIONS ====="
      
      options = args.extract_options!
      Kernel.p options
      options.reverse_merge! :flags => []
      db = options[:source_schema]

      # Database host when ssh'ed into the db server
      db_host = "127.0.0.1"
      Kernel.p "===== mysql_export_outfile ssh_configs ====="
      Kernel.p ssh_configs(db)
      if !ssh_configs(db)["ssh_db_host"].blank?
        db_host =  ssh_configs(db)["ssh_db_host"]
      elsif !db_configs(db)["host"].blank?
        db_host = db_configs(db)["host"]
      end
      
      flags = ""
      
      self.mysql_flags.each_pair do |flag, value|
        if options[:flags].include? flag
          flags += " --#{flag} "
        elsif value
          flags += " --#{flag} "
        end
      end
      
      cmd = Myreplicator.mysql
      cmd += "#{flags} "
      
      cmd += "-u#{db_configs(db)["username"]} -p#{db_configs(db)["password"]} "
      
      if db_configs(db).has_key? "socket"
        cmd += "--socket=#{db_configs(db)["socket"]} " 
      else
        cmd += "-h#{db_host} " if db_configs(db)["unuse_host_and_port"].blank?
        if db_configs(db)["unuse_host_and_port"].blank?
          cmd += db_configs(db)["port"].blank? ? "-P3306 " : "-P#{db_configs(db)["port"]} "
        end
      end
      
      cmd += "--execute=\"#{get_outfile_sql(options)}\" "
      Kernel.p cmd
      puts cmd
      return cmd
    end

    ##
    # Default flags for mysql export
    ## 
    def self.mysql_flags
      {"column-names" => false,
        "quick" => true,
        "reconnect" => true
      }    
    end

    ##
    # Builds SQL needed for incremental exports
    ##
    def self.export_sql *args
      options = args.extract_options!
      sql = "SELECT * FROM #{options[:db]}.#{options[:table]} " 
      
      if options[:incremental_col] && !options[:incremental_val].blank?
        if options[:incremental_col_type] == "datetime"
          sql += "WHERE #{options[:incremental_col]} >= '#{options[:incremental_val]}'"
        else
          sql += "WHERE #{options[:incremental_col]} >= #{options[:incremental_val]}"
        end
      end

      return sql
    end

    ##
    # Gets the Maximum value for the incremental 
    # column of the export job
    ##
    def self.max_value_sql *args
      options = args.extract_options!
      sql = ""

      if options[:incremental_col]
        
        if options[:incremental_col_type] == "datetime" && options[:max_incremental_value] == '0'
          options[:max_incremental_value] = "1900-01-01 00:00:00"
        end
        sql = "SELECT COALESCE(max(#{options[:incremental_col]}),'#{options[:max_incremental_value]}') FROM #{options[:db]}.#{options[:table]}" 
      else
        raise Myreplicator::Exceptions::MissingArgs.new("Missing Incremental Column Parameter")
      end
      
      return sql
    end
    
    def self.max_value_vsql *args
      options = args.extract_options!
      sql = ""
      
      if options[:incremental_col]
        sql = "SELECT max(#{options[:incremental_col]}) FROM #{options[:db]}.#{options[:table]}"
      else
        raise Myreplicator::Exceptions::MissingArgs.new("Missing Incremental Column Parameter")
      end
            
      return sql
    end
    
  end
end
