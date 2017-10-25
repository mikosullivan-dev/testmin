#!/usr/bin/ruby -w
require 'json'
require 'fileutils'
require 'open3'
require 'benchmark'
require 'timeout'
require 'time'
require 'optparse'


# Testmin is a simple, minimalist testing framework. Testmin is on GitHub at
# https://github.com/mikosullivan/testmin



################################################################################
# Testmin
#
module Testmin
	# Testmin version
	VERSION = '0.0.4'
	
	# export Testmin version to environment
	ENV['TESTMIN'] = VERSION
	
	# length for horizontal rules
	HR_LENGTH = 100
	
	# directory settings file
	DIR_SETTINGS_FILE = 'testmin.dir.json'
	GLOBAL_CONFIG_FILE = './testmin.config.json'
	
	# human languages (e.g. english, spanish)
	# For now we only have English.
	@human_languages = ['en']
	
	# if devshortcut() has been called
	@devshortcut_called = false
	
	# if Testmin should output directory hr's
	@dir_hrs = true
	
	# settings
	@settings = nil
	
	# exec_file
	# The realpath to the current executing file
	@exec_file = File.realpath(__FILE__)
	
	# command line settings
	@auto_submit = nil
	@silent = false
	@output = 'normal'
	@user_email = nil
	
	
	#---------------------------------------------------------------------------
	# DefaultSettings
	#
	DefaultSettings = {
		# timeout: set to 0 for no timeout
		'timeout' => 30,
		
		# should the user be prompted to submit the test results
		'submit' => {
			'request' => false,
			'email' => false,
			'comments' => false,
			
			'site' => {
				'root' => 'https://testmin.idocs.com',
				'submit' => '/submit',
				'project' => '/project',
				'entry' => '/entry',
				'title' => 'Idocs Testmin',
			},
		},
		
		# messages
		'messages' => {
			# English
			'en' => {
				# general purpose messages
				'success' => 'success',
				'failure' => 'failure',
				'yn' => '[Yes|No]',
				'root-dir' => 'root directory',
				'running-tests' => 'Running tests',
				'no-files-to-run' => 'no files to run',
				
				# messages about test results
				'test-success' => 'All tests run successfully',
				'test-failure' => 'There were some errors in the tests',
				'finished-testing' => 'finished testing',
				
				# submit messages
				'email-prompt' => 'email address',
				'submit-hold' => 'submitting',
				'submit-success' => 'done',
				'submit-failure' => 'Submission of test results failed. Errors: [[errors]]',
				'add-comments' => 'Add your comments here.',
				'entry-reference' => 'test results',
				'project-reference' => 'project results',
				
				# request to submit results
				'submit-request' => <<~TEXT,
				May this script submit these test results to [[title]]?
				The results will be submitted to the [[title]] service
				where they will be publicly available. In addition to the
				test results, the only information about your system will be
				the operating system and version, the version of Ruby, and
				the version of Testmin.
				TEXT
				
				# request to add email address
				'email-request' => <<~TEXT,
				Would you like to send your email address? Your email will
				not be publicly displayed. You will only be contacted to
				about this project.
				TEXT
				
				# request to add email address
				'comments-request' => <<~TEXT,
				Would you like to add some comments? Your comments will not
				be publicly displayed.
				TEXT
			},
			
			# Spanish
			# Did one message in Spanish just to test the system. Somebody
			# please feel free to add Spanish translations.
			'es' => {
				'submit-results' => '¿Envíe estos resultados de la prueba a [[title]]?'
			},
		},
	}
	#
	# DefaultSettings
	#---------------------------------------------------------------------------
	
	
	#---------------------------------------------------------------------------
	# done
	#
	def self.done(opts = {})
		# Testmin.hr(__method__.to_s)
		
		# cannot mark done if _devshortcut_called is true
		# if Settings['devshortcut_called']
		if @devshortcut_called
			raise 'devshortcut called, so cannot mark as done'
		end if
		
		# initialize hash
		opts = {'testmin-success'=>true}.merge(opts)
		
		# output done hash
		Testmin.v JSON.generate(opts)
		
		# exit
		exit
	end
	#
	# done
	#---------------------------------------------------------------------------

	
	#---------------------------------------------------------------------------
	# devshortcut
	#
	def self.devshortcut()
		@devshortcut_called = true
		return false
	end
	#
	# devshortcut
	#---------------------------------------------------------------------------


	#---------------------------------------------------------------------------
	# dir_settings
	#
	def self.dir_settings(log, run_dirs, dir_path, opts = {})
		# hr __method__.to_s + ': ' + dir_path.class.to_s
		
		# dir_path should be defined
		if dir_path.nil?
			puts Thread.current.backtrace.join("\n")
			exit
		end
		
		# normalize dir_path to remove trailing / if there is one
		dir_path = dir_path.gsub(/\/+\z/imu, '')
		
		# initialize directory properties and settings
		dir = {}
		dir['path'] = dir_path
		dir['settings'] = {}
		
		# build settings path
		settings_path = dir_path + '/' + DIR_SETTINGS_FILE
		
		# slurp in settings from directory settings file if it exists
		if File.exist?(settings_path)
			begin
				dir_settings = JSON.parse(File.read(settings_path))
				dir['settings'] = dir['settings'].merge(dir_settings)
			rescue Exception => e
				# verbosify.v
				Testmin.v 'error parsing directory settings file: ' + dir_path
				
				# note error in directory log
				dir['success'] = false
				dir['errors'] = [
					{
						'id'=>'Testmin.dir.json-parse-error',
						'exception-message' => e.message,
					}
				]
				
				# note that test run has failed
				log['success'] = false
				
				# return
				return false
			end
		end
		
		# TESTING
		# puts dir_settings
		
		# src: if a source directory is given, recurse to get that directory's
		# settings
		if not dir['settings']['src'].nil?
			return Testmin.dir_settings(
				log,
				run_dirs,
				dir['settings']['src'],
				{'dir-order'=>dir['settings']['dir-order']}
			)
		end
		
		# set dir-order
		if not opts['dir-order'].nil?
			dir['settings']['dir-order'] = opts['dir-order']
		else
			if dir['settings']['dir-order'].nil?()
				# special case: root dir defaults to -1 in order
				if dir_path == '.'
					dir['settings']['dir-order'] = -1
				else
					dir['settings']['dir-order'] = 1000000
				end
			end
		end
		
		# set default files
		if dir['settings']['files'].nil?()
			dir['settings']['files'] = {}
		else
			if not dir['settings']['files'].is_a?(Hash)
				raise 'files setting is not a hash for ' + dir_path
			end
		end
		
		# add to run_dirs
		run_dirs.push(dir)
		
		# return success
		return true
	end
	#
	# dir_settings
	#---------------------------------------------------------------------------
	
	
	#---------------------------------------------------------------------------
	# dir_check
	#
	def self.dir_check(log, dir)
		# Testmin.hr(__method__)
		
		# convenience variables
		files = dir['settings']['files']
		
		# array of files to add to files hash
		add_files = []
		
		# change into test dir
		Dir.chdir(dir['path']) do
			# unlist files that don't exist
			files.keys.each do |file_path|
				if not File.exist?(file_path)
					files.delete(file_path)
				end
			end
			
			# loop through files in directory
			Dir.glob('*').each do |file_path|
				# skip dev files
				if file_path.match(/\Adev\./)
					next
				end
				
				# must be executable
				if not File.executable?(file_path)
					next
				end
				
				# must be file, not directory
				if not File.file?(file_path)
					next
				end
				
				# don't execute self
				if File.realpath(file_path) == @exec_file
					next
				end
				
				# if file is not in files hash, add to array of unlisted files
				if not files.key?(file_path)
					add_files.push(file_path)
				end
			end
		end
		
		# sort add_files by file name
		add_files = add_files.sort
		
		# add files not listed in config file
		add_files.each do |file_path|
			files[file_path] = true
		end
		
		# return success
		return true
	end
	#
	# dir_check
	#---------------------------------------------------------------------------


	#---------------------------------------------------------------------------
	# dir_run
	#
	def self.dir_run(log, dir, dir_order)
		# Testmin.hr(__method__)
		
		# verbosify
		if @dir_hrs
			if dir['title'].nil?
				dir_path_display = dir['path']
				dir_path_display = dir_path_display.sub(/\A\.\//imu, '')
			else
				dir_path_display = dir['title']
			end
			
			Testmin.hr('title'=>dir_path_display, 'dash'=>'=')
		end
		
		# build hash key
		dir_key = + dir['path']
		
		# special case: root dir
		if dir_key == '.'
			dir_key = './'
		else
			dir_key = dir_key.gsub(/\A.\//imu, '')
		end
		
		# initialize success to true
		success = true
		
		# add directory to log
		dir_files = {}
		dir_log = {'dir-order'=>dir_order, 'files'=>dir_files}
		log['dirs'][dir_key] = dir_log
		
		# skip if marked to do so
		if dir['skip']
			Testmin.v "*** skipping ***\n\n"
			return true
		end
		
		# initialize files_run
		files_run = 0
		
		# change into test dir, run files
		Dir.chdir(dir['path']) do
			# initialize file_order
			file_order = 0
			
			# run test files in directory
			mark = Benchmark.measure {
				# loop through files
				dir['settings']['files'].each do |file_path, file_settings|
					# increment file order
					file_order = file_order + 1
					
					# run file
					success = Testmin.file_run(dir_files, file_path, file_settings, file_order)
					
					# if file_settings isn't the false object, increment files_run
					if not file_settings.is_a?(FalseClass)
						files_run += 1
					end
					
					# if failure, we're done
					if not success
						break
					end
				end
			}
			
			# note if no files run
			if files_run == 0
				Testmin.v Testmin.message('no-files-to-run')
			end
			
			# note run-time
			dir_log['run-time'] = mark.real
		end
		
		# add a little room underneath dir
		Testmin.v
		
		# return success
		return success
	end
	#
	# dir_run
	#---------------------------------------------------------------------------
	
	
	#---------------------------------------------------------------------------
	# get_file_settings
	#
	def self.get_file_settings(file_settings)
		# Testmin.hr(__method__)
		
		# if false
		if file_settings.is_a?(FalseClass)
			return nil
		end
		
		# if not a hash, make it one
		if not file_settings.is_a?(Hash)
			file_settings = {}
		end
		
		# set default file settings
		file_settings = {'timeout'=>Testmin.settings['timeout']}.merge(file_settings)
		
		# return
		return file_settings
	end
	#
	# get_file_settings
	#---------------------------------------------------------------------------
	
	
	#---------------------------------------------------------------------------
	# file_run
	# TODO: The code in this routine gets a litle spaghettish. Need to clean it
	# up.
	#
	def self.file_run(dir_files, file_path, file_settings, file_order)
		# Testmin.hr(__method__)
		
		# get file settings
		file_settings = Testmin.get_file_settings(file_settings)
		
		# if file_settings is nil, don't run this file
		if file_settings.nil?
			return true
		end
		
		# verbosify
		Testmin.v file_path
		
		# add to dir files list
		file_log = {'file-order'=>file_order}
		dir_files[file_path] = file_log
		
		# debug objects
		debug_stdout = ''
		debug_stderr = ''
		completed = true
		
		# run file with benchmark
		mark = Benchmark.measure {
			# run file with timeout
			Open3.popen3('./' + file_path) do |stdin, stdout, stderr, thread|
				begin
					Timeout::timeout(file_settings['timeout']) {
						debug_stdout = stdout.read.chomp
						debug_stderr = stderr.read.chomp
					}
				rescue
					Process.kill('KILL', thread.pid)
					file_log['timed-out'] = Testmin.settings['timeout']
					completed = false
				rescue
					completed = false
				end
			end
		}
		
		# if completed
		if completed
			# get results
			results = Testmin.parse_results(debug_stdout)
			
			# determine success
			if results.is_a?(Hash)
				# get success
				success = results.delete('testmin-success')
				
				# add other elements to details if any
				if results.any?
					file_log['details'] = results
					
					# set environment variables if any were sent
					if results['env'].is_a?(Hash)
						results['env'].each do |key, val|
							ENV[key] = val.to_s
						end
					end
				end
			else
				success = false
			end
		
		# else not completed
		else
			success = false
		end
		
		# add success and run time
		file_log['success'] = success
		file_log['run-time'] = mark.real
		
		# hold ton stdout and stderr if necessary
		if (not success) or file_settings['save-output']
			file_log['stdout'] = debug_stdout
			file_log['stderr'] = debug_stderr
		end
		
		# if failure
		if not success
			# show file output
			Testmin.v
			Testmin.hr('title'=>Testmin.message('failure'), 'dash'=>'*')
			Testmin.hr('stdout')
			Testmin.v debug_stdout
			Testmin.hr('stderr')
			Testmin.v debug_stderr
			Testmin.hr('dash'=>'*')
			Testmin.v
		end
		
		# return success
		return success
	end
	#
	# file_run
	#---------------------------------------------------------------------------


	#---------------------------------------------------------------------------
	# os_info
	#
	def self.os_info(versions)
		os = versions['os'] = {}
		
		# kernel version
		os['version'] = `uname -v`
		os['version'] = os['version'].strip
		
		# kernel release
		os['release'] = `uname -r`
		os['release'] = os['release'].strip
	end
	#
	# os_info
	#---------------------------------------------------------------------------
	
	
	#---------------------------------------------------------------------------
	# versions
	#
	def self.versions(log)
		# Testmin.hr(__method__.to_s)
		
		# initliaze versions hash
		versions = log['sys-info'] = {}
		
		# Testmin version
		versions['testmin'] = Testmin::VERSION
		
		# OS information
		Testmin.os_info(versions)
		
		# ruby version
		versions['ruby'] = RUBY_VERSION
	end
	#
	# versions
	#---------------------------------------------------------------------------


	#---------------------------------------------------------------------------
	# last_line
	#
	def self.last_line(str)
		# Testmin.hr(__method__)
		
		# early exit: str is not a string
		if not str.is_a?(String)
			return nil
		end
		
		# split into lines
		lines = str.split(/[\n\r]/)
		
		# loop through lines
		lines.reverse.each { |line|
			# if non-blank line, return
			if line.match(/\S/)
					return line
			end
		}
		
		# didn't find non-blank, return nil
		return nil
	end
	#
	# last_line
	#---------------------------------------------------------------------------
	
	
	#---------------------------------------------------------------------------
	# parse_results
	#
	def self.parse_results(stdout)
		# Testmin.hr(__method__)
		
		# get last line
		last_line = Testmin.last_line(stdout)
		
		# if we got a string
		if last_line.is_a?(String)
			if (last_line.match(/\A\s*\{/) and last_line.match(/\}\s*\z/))
				# attempt to parse
				begin
					rv = JSON.parse(last_line)
				rescue
					return nil
				end
				
				# should have gotten a hash
				if rv.is_a?(Hash)
					return rv
				end
			end
		end
		
		# the last line of stdout was not a Testmin results line, so return nil
		return nil
	end
	#
	# parse_results
	#---------------------------------------------------------------------------
	
	
	#---------------------------------------------------------------------------
	# get_results
	#
	def self.get_results(stdout)
		# Testmin.hr(__method__)
		
		# get results hash
		results = parse_results(stdout)
		
		# if hash, check for results
		if results.is_a?(Hash)
			success = results['testmin-success']
			
			# if testmin-success is defined
			if (success.is_a?(TrueClass) || success.is_a?(FalseClass))
				return results
			end
		end
		
		# didn't get a results line, do return nil
		return nil
	end
	#
	# get_results
	#---------------------------------------------------------------------------
	
	
	#---------------------------------------------------------------------------
	# create_log
	#
	def self.create_log()
		# initialize log object
		log = {}
		log['id'] = ('a'..'z').to_a.shuffle[0,10].join
		log['success'] = true
		log['dirs'] = {}
		log['private'] = {}
		log['timestamp'] = Time.new.to_s
		
		# get project id if there is one
		if not self.settings['project'].nil?
			log['project'] = self.settings['project']
		end
		
		# add system version info
		self.versions(log)
		
		# return
		return log
	end
	#
	# create_log
	#---------------------------------------------------------------------------
	
	
	#---------------------------------------------------------------------------
	# hr
	#
	def self.hr(opts={})
		# set opts from scalar or hash
		if opts.nil?
			opts = {}
		elsif not opts.is_a?(Hash)
			opts = {'title'=>opts}
		end
		
		# set default dash
		opts = {'dash'=>'-', 'title'=>''}.merge(opts)
		
		# output
		if opts['title'].to_s == ''
			self.v opts['dash'] * HR_LENGTH
		else
			self.v (opts['dash'] * 3) + ' ' + opts['title'].to_s + ' ' + (opts['dash'] * (HR_LENGTH - 5 - opts['title'].to_s.length))
		end
	end
	#
	# hr
	#---------------------------------------------------------------------------
	
	
	#---------------------------------------------------------------------------
	# randstr
	#
	def self.randstr()
		return (('a'..'z').to_a + (0..9).to_a).shuffle[0,8].join
	end
	#
	# randstr
	#---------------------------------------------------------------------------
		
	
	#---------------------------------------------------------------------------
	# val_to_bool
	#
	def self.val_to_bool(t)
		# self.hr(__method__.to_s)
		
		# String
		if t.is_a?(String)
			t = t.downcase
			t = t[0,1]
			
			# n, f, 0, or empty string
			if ['n', 'f', '0', ''].include? t
				return false
			end
			
			# anything else return true
			return true
		end
		
		# anything else return !!
		return !!t
	end
	#
	# val_to_bool
	#---------------------------------------------------------------------------
	
	
	#---------------------------------------------------------------------------
	# get_cmd_opts
	#
	def self.get_cmd_opts()
		# self.hr(__method__.to_s)
		
		# initialize return value
		rv = {}
		
		# get command line options
		OptionParser.new do |opts|
			# submit
			opts.on("-sSUBMIT", "--submit = y|n", 'submit results to an online service') do |val|
				rv['submit'] = self.val_to_bool(val)
			end
			
			# output
			opts.on("-o", "--output = normal|silent", 'run silently') do |val|
				rv['output'] = val
			end
			
			# email
			opts.on("-eEMAIL", "--email = email|n", 'ask for an email address') do |val|
				rv['email'] = val
			end
			
			# no-comments
			opts.on('-z', '--no-comments', 'do  not prompt for comments') do |bool|
				rv['no-comments'] = self.val_to_bool(val)
			end
			
			# version
			opts.on('-v', '--version', 'display version and quit') do
				rv['version'] = true
			end
		end.parse!
		
		# return
		return rv
	end
	#
	# get_cmd_opts
	#---------------------------------------------------------------------------
	
	
	#---------------------------------------------------------------------------
	# process_cmd_opts
	#
	def self.process_cmd_opts()
		# self.hr(__method__.to_s)
		
		# get options
		opts = Testmin.get_cmd_opts()
		
		# convenience
		submit = Testmin.settings['submit']
		
		# output
		if opts.key?('output')
			if opts['output'] == 'normal'
				@output = 'normal'
				@silent = false
			elsif opts['output'] == 'json'
				@output = 'json'
				@silent = true
				@auto_submit = true
			elsif opts['output'] == 'silent'
				@output = 'silent'
				@silent = true
				@auto_submit = true
			end
		end
		
		# version
		if opts.key?('version')
			if opts['version']
				# normal
				if @output == 'json'
					puts '{"version":"' + VERSION + '"}'
				else
					puts 'Testmin version ' + VERSION
				end
				
				# exit
				exit
			end
		end
		
		# submit
		if opts.key?('submit')
			# only bother if settings already indicate to submit results
			if submit['request']
				@auto_submit = opts['submit']
			end
		end
		
		# email
		if opts.key?('email')
			# only bother with these settings if asking for email
			if submit['email']
				bool = val.downcase
				
				# if false, set email to false
				if (bool == 'n') or (bool == '0') or (bool == 'f')
					submit['email'] = false
				else
					@user_email = val
				end
			end
		end
		
		# no comments
		if opts.key?('no-comments')
			submit['comments'] = false
		end
	end
	#
	# process_cmd_opts
	#---------------------------------------------------------------------------
	
	
	#---------------------------------------------------------------------------
	# v (verbose)
	#
	def self.v(str = '')
		# Testmin.hr(__method__.to_s)
		
		# if silent, do nothing
		if @silent
			return
		end
		
		# output string
		puts str
	end
	#
	# v (verbose)
	#---------------------------------------------------------------------------
	
	
	#---------------------------------------------------------------------------
	# vp (verbose print)
	#
	def self.vp(str = '')
		# Testmin.hr(__method__.to_s)
		
		# if silent, do nothing
		if @silent
			return
		end
		
		# output string
		print str
	end
	#
	# vp (verbose print)
	#---------------------------------------------------------------------------
	
	
	#---------------------------------------------------------------------------
	# run_tests
	#
	def self.run_tests()
		# Testmin.hr(__method__.to_s)
		
		# get command line options
		Testmin.process_cmd_opts()
		
		# initialize log object
		log = Testmin.create_log()
		
		# run tests, output results
		results = Testmin.process_tests(log)
		log['success'] = results
		
		# verbosify
		Testmin.v()
		Testmin.hr 'dash'=>'=', 'title'=>Testmin.message('finished-testing')
		
		# output succsss|failure
		if results
			Testmin.v Testmin.message('test-success')
		else
			Testmin.v Testmin.message('test-failure')
		end
		
		# bottom of section
		Testmin.hr 'dash'=>'='
		Testmin.v
		
		# send log to Testmin service if necessary
		Testmin.v
		Testmin.submit_results(log)
		
		# output json if necessary
		if @output == 'json'
			puts JSON.generate(log)
		end
	end
	#
	# run_tests
	#---------------------------------------------------------------------------
	
	
	#---------------------------------------------------------------------------
	# settings
	#
	def self.settings()
		# Testmin.hr(__method__.to_s)
		
		# if @settings is nil, initalize settings
		if @settings.nil?
			# if config file exists, merge it with
			if File.exist?(GLOBAL_CONFIG_FILE)
				# read in configuration file if one exists
				config = JSON.parse(File.read(GLOBAL_CONFIG_FILE))
				
				# merge with default settings
				@settings = DefaultSettings.deep_merge(config)
			end
			
			# if @settings is still nil, just clone DefaultSettings
			if @settings.nil?
				@settings = DefaultSettings.clone()
			end
		end
		
		# return settings
		return @settings
	end
	#
	# settings
	#---------------------------------------------------------------------------
	
	
	#---------------------------------------------------------------------------
	# yes_no
	#
	def self.yes_no(prompt)
		# Testmin.hr(__method__.to_s)
		
		# output prompt
		print prompt
		
		# get response until it's y or n
		loop do
			# output prompt
			print Testmin.message('yn') + ' '
			
			# get response
			response = $stdin.gets.chomp
			
			# normalize response
			response = response.gsub(/\A\s+/imu, '')
			response = response.downcase
			response = response[0,1]
			
			# if we got one of the matching letters, we're done
			if response == 'y'
				return true
			elsif response == 'n'
				return false
			end
		end
		
		# return
		# should never get to this point
		return response
	end
	#
	# yes_no
	#---------------------------------------------------------------------------
	
	
	#---------------------------------------------------------------------------
	# submit_ask
	#
	def self.submit_ask()
		# Testmin.hr(__method__.to_s)
		
		# if @auto_submit is set, use that as the return value
		if not @auto_submit.nil?
			return @auto_submit
		end
		
		# get submit settings
		submit = Testmin.settings['submit']
		
		# get prompt
		prompt = Testmin.message(
			'submit-request',
			'fields' => submit['site'],
		)
		
		# get results of user prompt
		return Testmin.yes_no(prompt)
	end
	#
	# submit_ask
	#---------------------------------------------------------------------------
	
	
	#---------------------------------------------------------------------------
	# email_ask
	#
	def self.email_ask(results)
		# Testmin.hr(__method__.to_s)
		
		# convenience
		submit = Testmin.settings['submit']
		
		# if not set to submit email, nothing to do
		if not submit['email']
			return true
		end
		
		# if user gave email in command line
		if not @user_email.nil?
			results['private']['email'] = @user_email
		
		# else if @auto_submit is nil, meaning the user has not already set a
		# choice on whether or not to submit
		elsif @auto_submit.nil?
			# get prompt
			prompt = Testmin.message(
				'email-request',
				'fields' => submit,
			)
			
			# add a little horizontal space
			Testmin.v
			
			# if the user wants to add email
			if not Testmin.yes_no(prompt)
				return true
			end
			
			# build prompt for getting email
			prompt = Testmin.message('email-prompt')
			
			# get email
			results['private']['email'] = Testmin.get_line(prompt)
		end
		
		# done
		return true
	end
	#
	# email_ask
	#---------------------------------------------------------------------------
	
	
	#---------------------------------------------------------------------------
	# comments_ask
	#
	def self.comments_ask(results)
		# Testmin.hr(__method__.to_s)
		
		# convenience
		submit = settings['submit']
		
		# if not set to submit comments, nothing to do
		if not submit['comments']
			return
		end
		
		# if automatic, nothing to do here
		if @auto_submit
			return
		end
		
		# early exit: no editor
		if ENV['EDITOR'].nil?
			return
		end
		
		# get prompt
		prompt = Testmin.message(
			'comments-request',
			'fields' => submit,
		)
		
		# add a little horizontal space
		Testmin.v
		
		# if the user does not want to add comments
		if not Testmin.yes_no(prompt)
			return
		end
		
		# build prompt for getting email
		prompt = Testmin.message('add-comments')
		
		# create comments file
		path = '/tmp/Testmin-comments-' + Testmin.randstr + '.txt'
		
		# create file
		File.open(path, 'w') { |file|
			file.write(prompt + "\n");
		}
		
		# open editor
		system(ENV['EDITOR'], path)
		
		# read in file
		results['private']['comments'] = File.read(path)
		
		# delete file
		if File.exist?(path)
			File.delete(path)
		end
		
		# done
		return
	end
	#
	# comments_ask
	#---------------------------------------------------------------------------
	
	
	#---------------------------------------------------------------------------
	# get_line
	#
	def self.get_line(prompt)
		# Testmin.hr(__method__.to_s)
		
		# loop until we get a line with some content
		loop do
			# get response
			print prompt + ': '
			response = $stdin.gets.chomp
			
			# if line has content, collapse and return it
			if response.match(/\S/)
				response = Testmin.collapse(response)
				return response
			end
		end
	end
	#
	# get_line
	#---------------------------------------------------------------------------
	
	
	#---------------------------------------------------------------------------
	# collapse
	#
	def self.collapse(str)
		# Testmin.hr(__method__.to_s)
		
		# only process defined strings
		if str.is_a?(String)
			str = str.gsub(/^[ \t\r\n]+/imu, '')
			str = str.gsub(/[ \t\r\n]+$/imu, '')
			str = str.gsub(/[ \t\r\n]+/imu, ' ')
		end
		
		# return
		return str
	end
	#
	# collapse
	#---------------------------------------------------------------------------
	
	
	#---------------------------------------------------------------------------
	# text_table
	#
	def self.text_table(table, opts={})
		widths = []
		hr = []
		
		# determine if bar separators are necessary
		bars = !opts['bars'].nil?
		
		# initialize return value
		rv = ''
		
		# calculate maximum widths
		table.each{|line|
			c = 0
			
			# loop through columns
			line.each{|col|
				# if bars, add two characters to col
				if bars
					col += ' '
				end
				
				# get widths
				widths[c] = (widths[c] && widths[c] > col.to_s.length) ? widths[c] : col.to_s.length
				c += 1
			}
		}
		
		# include widths of fields
		if opts['fields'].is_a?(Array)
			c = 0
			opts['fields'].each{|col|
				# if bars, add two characters to col
				if bars
					col += ' '
				end
				
				# get widths
				widths[c] = (widths[c] && widths[c] > col.to_s.length) ? widths[c] : col.to_s.length
				c += 1
			}
			
		end
		
		# build hr
		widths.each do |width|
			hr.push('-' * width)
		end
		
		# output top hr
		if bars
			rv += self.table_line(widths, hr, bars, 'show_bars'=>false)
		end
		
		# if title
		if opts['fields'].is_a?(Array)
			# output line
			rv += self.table_line(widths, opts['fields'], bars)
			
			# output top hr
			if bars
				rv += self.table_line(widths, hr, bars, 'show_bars'=>false)
			end
		end
		
		# print each line
		table.each do |line|
			rv += self.table_line(widths, line, bars)
		end
		
		# output bottom hr
		if bars
			rv += self.table_line(widths, hr, bars, 'show_bars'=>false)
		end
		
		# return
		return rv
	end
	#
	# text_table
	#---------------------------------------------------------------------------
	
	
	#---------------------------------------------------------------------------
	# table_line
	#
	def self.table_line(widths, line, bars, opts={})
		# default options
		opts = {'show_bars'=>true}.merge(opts)
		
		# initialize return value
		rv = ''
		
		# print each column
		line.each_with_index do |col, col_index|
			rv += self.field_col(widths, col, col_index, bars, opts)
		end
		
		# end of line
		rv += "\n"
		
		# return
		return rv
	end
	#
	# table_line
	#---------------------------------------------------------------------------
	
	
	#---------------------------------------------------------------------------
	# field_col
	#
	def self.field_col(widths, col, col_index, bars, opts)
		# initialize return value
		rv = ''
		
		# output with bars
		if bars
			# set bar
			if opts['show_bars']
				bar = '|'
			else
				bar = ' '
			end
			
			if col_index == 0
				rv += "#{bar}  " + col.to_s.ljust(widths[col_index])
			else
				rv += '  ' + col.to_s.ljust(widths[col_index]) + "  #{bar}"
			end
		
		# else output plain
		else
			if col_index == 0
				rv += col.to_s.ljust(widths[col_index])
			else
				rv += '  ' + col.to_s.ljust(widths[col_index])
			end
		end
		
		# return
		return rv
	end
	#
	# field_col
	#---------------------------------------------------------------------------
	
	
	#---------------------------------------------------------------------------
	# showhash
	#
	def self.showhash (myhash)
		# Testmin.hr __method__.to_s
		
		output = []
		
		myhash.each do |key, val|
			output.push([key, val])
		end
		
		puts Testmin.text_table(output)
		
		# rv = "<table border=1>\n"
		# keys = myhash.keys.sort
		#
		# keys.each do |key, val|
		# 	rv =
		# 		rv +
		# 		"<tr>\n" +
		# 		"<td>" + CGI::escapeHTML(key.to_s) + "</td>\n" +
		# 		"<td><pre>" + CGI::escapeHTML(myhash[key].to_s) + "</pre></td>\n" +
		# 		"</tr>\n"
		# end
		#
		# rv = rv + "</table>\n"
		#
		# # return
		# return rv
	end
	
	# KLUDGE: still can't figure out how to alias show_hash to showhash, so just
	# writing another method for now.
	def self.show_hash (myhash)
		return self.showhash (myhash)
	end
	
	#
	# showhash
	#---------------------------------------------------------------------------
	

	#---------------------------------------------------------------------------
	# showarr
	#
	def self.showarr(myarr, opts={})
		# default
		opts = {'title'=>true, 'show-nil'=>false}.merge(opts)
		
		# top bar
		puts '--- array: ' + myarr.length.to_s + ' -----------------'
		
		# if nil
		if myarr.nil?
			puts '[nil]'
		
		# else show elements in array
		else
			# clone
			usearr = myarr.clone
			
			# if it's not an array, make it one
			if ! usearr.is_a?(Array)
				usearr = [usearr]
			end
			
			# if empty
			if usearr.length == 0
				puts '[empty array]'
				puts '------------------------------'
			
			# else there's stuff in the array
			elsif
				usearr.each do |el|
					# if nil
					if el.nil?
						puts '[nil]'
					
					# else if string
					elsif el.is_a?(String)
						# if any non-spaces
						if el.match(/\S/imu)
							# collapse spaces
							el = el.sub(/\A\s+/imu, '')
							el = el.sub(/\s+\z/imu, '')
							el = el.gsub(/\s+/imu, ' ')
							
							# output
							puts el
						
						# else non-content string
						else
							puts '[nc]'
						end
					
					# else other object
					else
						puts el.to_s
					end
					
					# output separator
					puts '------------------------------'
				end
			end
		end
	end
	
	# KLUDGE: still can't figure out how to alias show_hash to showhash, so just
	# writing another method for now.
	def self.show_arr(myarr, opts={})
		return self.showarr(myarr, opts)
	end
	
	#
	# showarr
	#---------------------------------------------------------------------------
	
	
	#---------------------------------------------------------------------------
	# submit_results
	# TODO: Need to generalize this routine for submitting to other test
	# logging sites.
	#
	def self.submit_results(results)
		# Testmin.hr(__method__.to_s)
		
		# load settings
		settings = Testmin.settings
		
		# if not set to submit, nothing to do
		if not settings['submit']['request']
			return true
		end
		
		# check if the user wants to submit the test results
		if not Testmin.submit_ask()
			return true
		end
		
		# get email address
		Testmin.email_ask(results)
		
		# get comments
		Testmin.comments_ask(results)
		
		# load some modules
		require "net/http"
		require "uri"
		
		# get site settings
		site = settings['submit']['site']
		
		# verbosify
		Testmin.v
		Testmin.vp Testmin.message('submit-hold') + '...'
		
		# post
		url = URI.parse(site['root'] + site['submit'])
		params = {'test-results': JSON.generate(results)}
		response = Net::HTTP.post_form(url, params)
		
		# check results
		if response.is_a?(Net::HTTPOK)
			# parse json response
			response = JSON.parse(response.body)
			
			# output success or failure
			if response['success']
				Testmin.submit_success(site, results)
			else
				# initialize error array
				errors = []
				
				# build array of errors
				response['errors'].each do |error|
					errors.push error['id']
				end
				
				# output message
				Testmin.v Testmin.message('submit-failure', {'errors'=>errors.join(', ')})
			end
		else
			raise "Failed at submitting results. I have not yet implemented giving a good message for this situation yet."
		end
		
		# return success
		# NOTE: returning success only indicates that this function ran all the
		# way through, not that the results were successfully submitted.
		return true
	end
	#
	# submit_results
	#---------------------------------------------------------------------------
	
	
	#---------------------------------------------------------------------------
	# submit_success
	#
	def self.submit_success(site, results)
		# Testmin.hr(__method__.to_s)
		
		# load cgi libary
		require 'cgi'
		
		# output success
		Testmin.v ' ' + Testmin.message('submit-success')
		Testmin.v
		
		# initialize table
		table = []
		
		# entry link url
		entry_url =
			site['root'] +
			site['entry'] +
			'?id=' +
			CGI.escape(results['id'])
		
		# entry link
		table.push([
			Testmin.message('entry-reference') + ':',
			entry_url
		])
		
		# project link
		if not results['project'].nil?
			# project link url
			project_url =
				site['root'] +
				site['project'] +
				'?id=' +
				CGI.escape(results['project'])
			
			# entry link
			table.push([
				Testmin.message('project-reference') + ':',
				project_url
			])
		end
		
		# output urls
		puts Testmin.text_table(table)
	end
	#
	# submit_success
	#---------------------------------------------------------------------------
	
	
	#---------------------------------------------------------------------------
	# message
	#
	def self.message(message_id, opts={})
		# Testmin.hr(__method__.to_s)
		
		# default options
		opts = {'fields'=>{}, 'root'=>Testmin.settings['messages']}.merge(opts)
		fields = opts['fields']
		root = opts['root']
		
		# loop through languages
		@human_languages.each do |language|
			# if the template exists in this language
			if root[language].is_a?(Hash)
				# get tmeplate
				template = root[language][message_id]
				
				# if we actually got a template, process it
				if template.is_a?(String)
					# field substitutions
					fields.each do |key, val|
						# TODO: need to meta quote the key name
						template = template.gsub(/\[\[\s*#{key}\s*\]\]/imu, val.to_s)
					end
					
					# return
					return template
				end
			end
		end
		
		# we didn't find the template
		raise 'do not find message with message id "' + message_id + '"'
	end
	#
	# message
	#---------------------------------------------------------------------------
	
	
	#---------------------------------------------------------------------------
	# process_tests
	# This routine does the actual job of running the tests. It returns false
	# when an error is reached. If it gets to the end it returns true.
	#
	def self.process_tests(log)
		# Testmin.hr(__method__.to_s)
		
		# create test_id
		ENV['testmin_test_id'] = Testmin.randstr
		
		# initialize dirs array
		run_dirs = []
		
		# start with current directory
		if not Testmin.dir_settings(log, run_dirs, './')
			return false
		end
		
		# prettify dir settings for current directory
		if run_dirs[0]['title'].nil?
			run_dirs[0]['title'] = '[' + Testmin.message('root-dir') + ']'
		end
		
		# get list of directories
		Dir.glob('./*/').each do |dir_path|
			if not Testmin.dir_settings(log, run_dirs, dir_path)
				return false
			end
		end
		
		# sort on dir-order setting
		run_dirs = run_dirs.sort { |x, y| x['settings']['dir-order'] <=> y['settings']['dir-order'] }
		
		# check each directory settings
		run_dirs.each do |dir|
			if not Testmin.dir_check(log, dir)
				return false
			end
		end
		
		# if only the root directory, don't bother outputting the HR for it
		if run_dirs.length == 1
			@dir_hrs = false
		end
		
		# initialize dir_order
		dir_order = 0
		
		# initialize success to true
		success = true
		
		# verbosify
		Testmin.v Testmin.message('running-tests')
		
		# loop through directories
		mark = Benchmark.measure {
			run_dirs.each do |dir|
				# incremement dir_order
				dir_order = dir_order + 1
				
				# run directory
				success = Testmin.dir_run(log, dir, dir_order)
				
				# if not success, we're done looping
				if not success
					break
				end
			end
		}
		
		# note run time
		log['run-time'] = mark.real
		
		# success
		return success
	end
	#
	# process_tests
	#---------------------------------------------------------------------------
	
	
	#===========================================================================
	# ruby utilities for running tests
	#
	
	# isa
	def self.isa(test_name, my_object, class_should, opts={})
		# hr __method__.to_s
		
		# default options
		opts = {'should'=>true}.merge(opts)
		
		if opts['should']
			if not my_object.is_a?(class_should)
				raise test_name + ' - isa: should be class ' + class_should.to_s + ' but instead is class ' + my_object.class.to_s
			end
		else
			if my_object.is_a?(class_should)
				raise test_name + 'isa-should-not: should not be class ' + class_should.to_s + ' but is'
			end
		end	#
	end
	
	# comp
	def self.comp(test_name, is, should, opts={})
		# hr __method__.to_s
		
		# default options
		opts = {'should'=>true, 'collapse'=>false}.merge(opts)
		
		# collapse
		if opts['collapse']
			is = Testmin.collapse(is)
			should = Testmin.collapse(should)
		end
		
		# test
		if opts['should']
			if is != should
				tmfail test_name, "not equal\nis: " + is.to_s() + "\nshould: " + should.to_s()
			end
		else
			if is == should
				tmfail test_name, "equal\nis: " + is.to_s() + "\nshould: " + should.to_s()
			end
		end
		
		# return
		return true
	end
	
	# defined
	def self.defined(test_name, object, opts={})
		# hr __method__.to_s
		
		# default options
		opts = {'should'=>true}.merge(opts)
		
		# test
		if opts['should']
			if object.nil?
				tmfail(test_name, 'not defined but should be')
			end
		else
			if not object.nil?
				tmfail(test_name, 'defined but should not be')
			end
		end
		
		# return
		return true
	end
	
	# nil
	def self.is_nil(test_name, object, opts={})
		opts = opts.merge('should'=>false)
		return defined(test_name, object, opts)
	end
	
	# tmfail
	def self.tmfail(test_name, message)
		# hr __method__
		
		# title
		puts
		hr 'dash'=>'='
		puts '= fail: ' + test_name
		puts '='
		puts
		
		# output message
		hr 'title' => 'error'
		puts message
		
		# output stack
		puts
		hr 'title' => 'stack'
		puts caller
		
		# bottom
		puts
		puts '='
		puts '= fail: ' + test_name
		hr 'dash'=>'='
		puts
		
		# we're done
		exit
	end
	
	# devexit
	def self.devexit()
		# self.hr(__method__.to_s)
		puts "\n", '[devexit]'
		exit
	end
	
	# bool
	def self.bool(test_name, is, should, opts={})
		# hr __method.to_s__
		
		# default options
		opts = {'should'=>true}.merge(opts)
		
		# should should be defined
		if should.nil?
			raise ExceptionPlus::Internal.new('bool~should-not-defined', 'jzVjv', '"should" is not defined')
		end
		
		# test
		if should
			if not is
				tmfail(test_name, 'should be true but is not')
			end
		else
			if is
				tmfail(test_name, 'should not be true but is')
			end
		end
		
		# return
		return true
	end
	
	# bool_comp
	# Not a test. Returns true if the values are either both true or
	def self.bool_comp(a, b)
		# hr __method.to_s__
		
		# both true
		if a and b
			return true
		elsif (not a) and (not b)
			return true
		else
			return false
		end
	end
	
	# has_key
	def self.has_key(test_name, hash, key, opts={})
		# hr __method__.to_s
		
		# default options
		opts = {'should'=>true}.merge(opts)
		
		# get is
		is = hash.key?(key)
		
		# test
		if opts['should']
			if not is
				tmfail(test_name, 'should have key ' + key + ' but does not')
			end
		else
			if is
				tmfail(test_name, 'should have not key ' + key + ' but does')
			end
		end
		
		# return
		return true
	end
	
	#
	# ruby utilities for running tests
	#===========================================================================
	
end
#
# Testmin
################################################################################


################################################################################
# Array
#
class ::Array
	def show()
		return '[' + self.join('|') + ']'
	end
	
	def Array.as_a(el)
		if el.is_a?(Array)
			return el
		else
			return [el]
		end
	end
end
#
# Array
################################################################################



################################################################################
# Hash
#
class ::Hash
	def deep_merge(second)
		merger = proc { |key, v1, v2| Hash === v1 && Hash === v2 ? v1.merge(v2, &merger) : v2 }
		self.merge(second, &merger)
	end
end
#
# Hash
################################################################################



#---------------------------------------------------------------------------
# run tests if this script was not loaded by another script
#
if caller().length <= 0
	Testmin.run_tests()
end
#
# run tests if this script was not loaded by another script
#---------------------------------------------------------------------------
