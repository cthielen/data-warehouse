# Parses information from Banner into Ruby-based ORM modeling

namespace :iam do
  desc 'Runs the IAM import. Takes approx. ?? minutes.'
  task :import, [:iam_id] => :environment do |t, args|
    require 'net/http'
    require 'json'
    require 'yaml'

    # In case you receive SSL certificate verification errors
    require 'openssl'
    OpenSSL::SSL::VERIFY_PEER = OpenSSL::SSL::VERIFY_NONE

    Bundler.require

    load 'UcdLookups.rb'

    IAM_SETTINGS_FILE = "config/iam.yml"

    @total = @successfullySaved = @erroredOut = @noKerberos = 0
    timestamp_start = Time.now

    ### Import the IAM site and key from the yaml file
    if File.file?(IAM_SETTINGS_FILE)
      $IAM_SETTINGS = YAML.load_file(IAM_SETTINGS_FILE)
      @site = $IAM_SETTINGS['HOST']
      @key = $IAM_SETTINGS['KEY']
      @iamId = args.iam_id
    else
      puts "You need to set up config/iam.yml before running this application."
      exit
    end

    ### Method to get individual info
    def fetch_by_iamId(id)
      begin
        ## Fetch the person
        url = "#{@site}iam/people/search/?iamId=#{id}&key=#{@key}&v=1.0"
        # Fetch URL
        resp = Net::HTTP.get_response(URI.parse(url))
        # Parse results
        buffer = resp.body
        result = JSON.parse(buffer)

        first = result["responseData"]["results"][0]["dFirstName"]
        middle = result["responseData"]["results"][0]["oMiddleName"]
        last = result["responseData"]["results"][0]["dLastName"]
        isEmployee = result["responseData"]["results"][0]["isEmployee"]
        isFaculty = result["responseData"]["results"][0]["isFaculty"]
        isStudent = result["responseData"]["results"][0]["isStudent"]
        isStaff = result["responseData"]["results"][0]["isStaff"]

        ## Fetch the contact info
        url = "#{@site}iam/people/contactinfo/#{id}?key=#{@key}&v=1.0"
        # Fetch URL
        resp = Net::HTTP.get_response(URI.parse(url))
        # Parse results
        buffer = resp.body
        result = JSON.parse(buffer)

        email = result["responseData"]["results"][0]["email"]
        phone = result["responseData"]["results"][0]["workPhone"]
        address = result["responseData"]["results"][0]["postalAddress"]

        ## Fetch the kerberos userid
        url = "#{@site}iam/people/prikerbacct/#{id}?key=#{@key}&v=1.0"
        # Fetch URL
        resp = Net::HTTP.get_response(URI.parse(url))
        # Parse results
        buffer = resp.body
        result = JSON.parse(buffer)

        begin
          loginid = result["responseData"]["results"][0]["userId"]
        rescue
          puts "ID# #{id} does not have a loginId in IAM"
        end

        ## Fetch the association
        url = "#{@site}iam/associations/pps/search?iamId=#{id}&key=#{@key}&v=1.0"
        # Fetch URL
        resp = Net::HTTP.get_response(URI.parse(url))
        # Parse results
        buffer = resp.body
        result = JSON.parse(buffer)

        associations = result['responseData']['results']


        ## Fetch the student associations
        url = "#{@site}iam/associations/sis/#{id}?key=#{@key}&v=1.0"
        # Fetch URL
        resp = Net::HTTP.get_response(URI.parse(url))
        # Parse results
        buffer = resp.body
        result = JSON.parse(buffer)

        student_associations = result['responseData']['results']


        ## Insert results in database
        puts "IAM_ID: #{id}:"
        person = Person.find_or_create_by_iamId(iamId: id)
        person.first = first
        person.last = last
        person.email = email
        unless phone.nil?
          person.phone = phone
        end
        person.address = address
        person.loginid = loginid

        # PPS Associations
        associations.each do |a|
          # person.relationships << relationship unless person.relationships.include?(relationship) # Avoid duplicates
          puts "\t- #{a['deptOfficialName']}"
          puts "\t\t- Title #{a['titleOfficialName']}"
        end

        # SIS Associations
        student_associations.each do |a|
          puts "\t- #{a['majorName']}"
          puts "\t\t- Title #{a['levelName']}"
        end

        # Comparing affiliations
        puts "\t- Faculty Status: (#{isFaculty})"
        puts "\t- Staff Status: (#{isStaff})"
        puts "\t- Student Status: (#{isStudent})"

        
        @successfullySaved += 1 if person.save
      rescue StandardError => e
        puts "Cannot process ID#: #{id} -- #{e.message} #{e.backtrace.inspect}"
        @erroredOut += 1
      end
    end


    ### Fetch for all people in UcdLookups departments
    for d in UcdLookups::DEPT_CODES.keys()
      ## Fetch department members
      url = "#{@site}iam/associations/pps/search?deptCode=#{d}&key=#{@key}&v=1.0"

      # Fetch URL
      resp = Net::HTTP.get_response(URI.parse(url))
      # Parse results
      buffer = resp.body
      result = JSON.parse(buffer)

      # loop over members
      result["responseData"]["results"].each do |p|
        @total += 1
        iamID = p["iamId"]
        url = "#{@site}iam/people/prikerbacct/#{iamID}?key=#{@key}&v=1.0"
        # Fetch URL
        resp = Net::HTTP.get_response(URI.parse(url))
        # Parse results
        buffer = resp.body
        result = JSON.parse(buffer)

        loginid = result["responseData"]["results"][0]["userId"]
        fetch_by_iamId(iamID)
      end
    end
    for m in UcdLookups::MAJORS.values()
      puts "Processing graduate students in #{m}".magenta
      url = "#{@site}iam/associations/sis/search?collegeCode=GS&majorCode=#{m}&key=#{@key}&v=1.0"
      # Fetch URL
      resp = Net::HTTP.get_response(URI.parse(url))
      # Parse results
      buffer = resp.body
      result = JSON.parse(buffer)

      result["responseData"]["results"].each do |p|
        @total += 1
        iamID = p["iamId"]
        url = "#{@site}iam/people/prikerbacct/#{iamID}?key=#{@key}&v=1.0"
        # Fetch URL
        resp = Net::HTTP.get_response(URI.parse(url))
        # Parse results
        buffer = resp.body
        result = JSON.parse(buffer)
        loginid = result["responseData"]["results"][0]["userId"]
        fetch_by_iamId(iamID)
      end
    end

    timestamp_finish = Time.now

    puts "\n\nFinished processing a total of #{@total}:\n"
    puts "\t- #{@successfullySaved} successfully saved.\n"
    puts "\t- #{@noKerberos} did not have LoginID in IAM.\n"
    puts "\t- #{@erroredOut} errored out due to some missing fields.\n"
    puts "Time elapsed: " + Time.at(timestamp_finish - timestamp_start).gmtime.strftime('%R:%S')
    
  end
end