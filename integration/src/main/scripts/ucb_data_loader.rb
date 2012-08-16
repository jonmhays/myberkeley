#!/usr/bin/env ruby

require 'rubygems'
require 'json'
require 'digest/sha1'
require 'logger'
require 'nakamura'
require 'nakamura/users'
require 'nakamura/authz'
include SlingInterface
include SlingUsers

module MyBerkeleyData
  BASIC_PROFILE_PROPS = [
    'firstName', 'lastName'
  ]
  INSTITUTIONAL_PROFILE_PROPS = [
    'role', 'college', 'major'
  ]

  UG_GRAD_FLAG_MAP = {:U => 'Undergraduate Student', :G => 'Graduate Student'}
  STUDENT_ROLES = ["Undergraduate Student", "Graduate Student", "Student"]
  COLLEGE_ABBR_TO_PROFILE = { "ENV DSGN" => "College of Environmental Design", "NAT RES" => "College of Natural Resources" }
  ENV_PROD = 'prod'

  # Test data for development environments
  TEST_DYNAMIC_LIST_CONTEXTS = ["myb-ced-students-Advisers", "myb-cnr-students-Advisers",
    "myb-staff"]
  TEST_DEMOGRAPHICS = [{
      "college" => "ENV DSGN",
      "undergradMajors" => [ "ARCHITECTURE", "INDIVIDUAL", "LIMITED", "LANDSCAPE ARCH", "URBAN STUDIES" ],
      "gradMajors" => [ "ARCHITECTURE", "CITY REGIONAL PLAN", "DESIGN", "LIMITED", "LAND ARCH & ENV PLAN", "URBAN DESIGN" ]
    }, {
      "college" => "NAT RES",
      "undergradMajors" => [ "AGR & RES ECON", "CONSERV&RSRC STUDIES", "ENV ECON & POLICY", "ENVIR SCIENCES", "FOREST & NATURAL RES", "GENETICS & PLANT BIO",
        "MICROBIAL BIOLOGY", "MOL ENV BIOLOGY", "MOLECULAR TOXICOLOGY", "NUTR SCI-DIETETICS", "NUTR SCI-PHYS & MET", "NUTRITION SCIENCE", "SOCIETY&ENVIRONMENT",
        "UNDECLARED", "VISTOR-NON-UC CAMPUS" ],
      "gradMajors" => [ "AGR & RES ECON", "AGRICULTURAL CHEM", "COMP BIOCHEMISTRY", "ENV SCI POL AND MGMT", "FORESTRY", "PLANT BIOLOGY", "RANGE MANAGEMENT" ]
    }]
  TEST_EDUC_LEVEL_U = ["Freshman", "Senior", "Sophomore", "Junior"]
  TEST_EDUC_LEVEL_G = ["Masters", "Adv Doc", "Doctoral"]
  TEST_NEW_TRFR_FLAG = ["N", "Y", nil]
  TEST_DEG_ABBREV_U = ["A.B.", "B.S."]
  TEST_DEG_ABBREV_G = ["M.A.", "PH.D.", "M.B.A.", "M.S.", "JURIS.D", "M.P.P."]
  CALNET_TEST_USER_IDS = ["test-300846","test-300847","test-300848","test-300849","test-300850","test-300851",
    "test-300852","test-300853","test-300854","test-300855","test-300856","test-300857","test-300858",
    "test-300859","test-300860","test-300861","test-300862","test-300863","test-300864","test-300865",
    "test-300866","test-300867","test-300868","test-300869","test-300870","test-300871","test-300872",
    "test-300873","test-300874","test-300875","test-300876","test-300877"]

  class UcbDataLoader
    attr_reader :sling
    TEST_USER_PREFIX = 'testuser'

    @env = nil
    @user_manager = nil
    @sling = nil
    @authz = nil

    def initialize(server, admin_password="admin")
      @log = Logger.new(STDOUT)
      @log.level = Logger::DEBUG
      @sling = Sling.new(server, true)
      @user_manager = UserManager.new(@sling)
      real_admin = User.new("admin", admin_password)
      @sling.switch_user(real_admin)
      @sling.do_login
      @authz = SlingAuthz::Authz.new(@sling)
      @server = server
      @known_groups = []
    end

    def get_all_ucb_accounts
      res = @sling.execute_get(@sling.url_for("system/myberkeley/userIds.json"))
      if (res.code != "200")
        @log.error("Could not get existing integrated users: #{res.code} / #{res.body}")
        return nil
      else
        return JSON.parse(res.body)
      end
    end

    def add_user_to_group(user_id, group_id)
      if (!(@known_groups.include?(group_id)))
        result = @sling.execute_get(@sling.url_for("/system/userManager/group/#{group_id}.json"))
        if (result.code != "200")
          result = @sling.execute_post(@sling.url_for("/system/userManager/group.create.html"), {
            ":name" => group_id
          })
          if (result.code != "200")
            @log.error("Could not create group #{group_id}")
            return nil
          end
        end
        @known_groups.push(group_id)
      end
      result = @sling.execute_post(@sling.url_for("/system/userManager/group/#{group_id}.update.html"), {
        ":member" => user_id
      })
      @log.error("#{result.code} / #{result.body}") if (result.code.to_i > 299)
    end

    def load_dev_advisers
      all_data = JSON.load(File.open "dev_advisers_json.js", "r")
      users = all_data['users']
      loaded_users = Array.new
      users.each do |user|
        loaded_user = load_defined_adviser user
        puts "loaded user: #{loaded_user.inspect}"
        if (loaded_user)
          TEST_DYNAMIC_LIST_CONTEXTS.each do |context_id|
            add_user_to_group(loaded_user.name, context_id)
          end
          loaded_users << loaded_user
        end
      end
      return loaded_users
    end

    def load_defined_adviser user
        username = user[0]
        user_props = user[1]
        make_adviser_props user_props
        (loaded_user, new_user) = load_user username, user_props, "testuser"
        return loaded_user
    end

    def make_adviser_props user_props #need to have firstName, lastName and email loaded already
        user_props['role'] = 'Staff'
    end

    def load_calnet_test_users
      i = 0
      CALNET_TEST_USER_IDS.each do |id|
        first_name = id.split('-')[0].to_s
        last_name = id.split('-')[1].to_s
        uid = id.split('-')[1].to_s
        # for a user like test-212381, the calnet uid will be 212381
        user_props = generate_student_props uid, first_name, last_name, i, CALNET_TEST_USER_IDS.length
        (loaded_calnet_test_user, new_user) = load_user uid, user_props, "testuser"
        i = i + 1
      end
    end

    def generate_student_props(username, first_name, last_name, index, length)
        user_props = {}
        user_props[':name'] = username
        user_props['firstName'] = first_name.chomp
        user_props['lastName'] = last_name.chomp
        user_props['email'] = first_name.downcase + '.' + last_name.downcase + '@berkeley.edu'
        demog = TEST_DEMOGRAPHICS[index % TEST_DEMOGRAPHICS.length]
        user_props['college'] = COLLEGE_ABBR_TO_PROFILE[demog["college"]]
        if (index < length/2)
          user_props['role'] = UG_GRAD_FLAG_MAP[:U]
          majors_demog = demog["undergradMajors"]
          user_props['major'] = majors_demog[index % majors_demog.length]
          user_props['myb-demographics'] = [
            "/colleges/#{demog['college']}/standings/undergrad",
            "/colleges/#{demog['college']}/standings/undergrad/majors/" + user_props['major'],
            "/student/educ_level/#{TEST_EDUC_LEVEL_U[index % TEST_EDUC_LEVEL_U.length]}",
            "/student/deg_abbrev/#{TEST_DEG_ABBREV_U[index % TEST_DEG_ABBREV_U.length]}"
          ]
        else
          user_props['role'] = UG_GRAD_FLAG_MAP[:G]
          majors_demog = demog["gradMajors"]
          user_props['major'] = majors_demog[index % majors_demog.length]
          deg_abbrev = TEST_DEG_ABBREV_G[index % TEST_DEG_ABBREV_G.length]
          user_props['myb-demographics'] = [
            "/colleges/#{demog['college']}/standings/grad",
            "/colleges/#{demog['college']}/standings/grad/majors/" + user_props['major'],
            "/student/educ_level/#{TEST_EDUC_LEVEL_G[index % TEST_EDUC_LEVEL_G.length]}",
            "/student/deg_abbrev/#{deg_abbrev}"
          ]
          if (index == length - 1)
            user_props['myb-demographics'].push("/colleges/#{demog['college']}/standings/grad/majors/DOUBLE")
            user_props['myb-demographics'].push("/colleges/#{demog['college']}/standings/grad/majors/PSYCHOLOGY")
            # Basic Profile only handles single-valued string properties
            user_props['major'] = "DOUBLE : " + user_props['major'] + " ; " + "PSYCHOLOGY"
          end
        end
        trfr = TEST_NEW_TRFR_FLAG[index % TEST_NEW_TRFR_FLAG.length]
        user_props['myb-demographics'].push("/student/new_trfr_flag/#{trfr}") if (!trfr.nil?)
        return user_props
    end

    def load_demo_users
      all_data = JSON.load(File.open "demo_users_json.js", "r")
      users = all_data['users']
      loaded_users = Array.new
      users.each do |user|
        loaded_user = load_defined_demo_user user
        puts "loaded user: #{loaded_user.inspect}"
      end
      return loaded_users
    end

    def load_defined_demo_user user
        username = user[0]
        user_props = user[1]
        (loaded_user, new_user) = load_user username, user_props, "testuser"
        return loaded_user
    end

    def getBasicProfileContent(user_props)
      basicProps = []
      BASIC_PROFILE_PROPS.each do |prop|
        propval = user_props[prop]
        if (!propval.nil?)
          # Escape single quotes and backslashes
          propval = propval.gsub(/\\|'/) { |c| "\\#{c}" }
          basicProps.push("'#{prop}':{'value':'#{propval}'}")
        end
      end

      profileContentString = "{'basic':{'elements':{#{basicProps.join(",")}}}}"
      return profileContentString
    end

    def getProfileContent(user_props)
      basicProps = []
      BASIC_PROFILE_PROPS.each do |prop|
        propval = user_props[prop]
        if (!propval.nil?)
          # Escape single quotes and backslashes
          propval = propval.gsub(/\\|'/) { |c| "\\#{c}" }
          basicProps.push("'#{prop}':{'value':'#{propval}'}")
        end
      end
      institutionalProps = []
      INSTITUTIONAL_PROFILE_PROPS.each do |prop|
        propval = user_props[prop]
        if (!propval.nil?)
          # Escape single quotes and backslashes
          propval = propval.gsub(/\\|'/) { |c| "\\#{c}" }
          institutionalProps.push("'#{prop}':{'value':'#{propval}'}")
        end
      end

      profileContentString = "{'basic':{'elements':{#{basicProps.join(",")}}}"
      profileContentString += ",'email':{'elements':{'email':{'value':'#{user_props['email']}'}}}"
      profileContentString += ",'institutional':{'elements':{#{institutionalProps.join(",")}}}}"
      return profileContentString
    end

    def load_user(username, user_props, password=nil)
      @log.info("load_user #{username} with props #{user_props.inspect} and password #{password}")
      provision_props = user_props.clone
      if (password)
        provision_props["pwd"] = password
      end
      provision_props["userId"] = username
      res = @sling.execute_post(@sling.url_for("system/myberkeley/testPersonProvision"), provision_props)
      @log.info("provision returned #{res.code}, #{res.body}")
      if (res.code.to_i > 299)
        @log.error("Could not load user #{username}: #{res.code}, #{res.body}")
        return nil, false
      end
      json = JSON.parse(res.body)
      if (json["synchronizationState"] == "error")
        return nil, false
      end
      new_user = (json["synchronizationState"] == "created")
      if (password)
        target_user = User.new username, password
      else
        target_user = User.new username
      end
      return target_user, new_user
    end

    def is_participant?(uid)
      response = @sling.execute_get("#{@server}~#{uid}/public/authprofile/myberkeley/elements/participant.json")
      (response.code.to_i != 404)
    end

  end
end

if ($PROGRAM_NAME.include? 'ucb_data_loader.rb')
  puts "will load data on server #{ARGV[0]}"
  sdl = MyBerkeleyData::UcbDataLoader.new ARGV[0], ARGV[1]
  sdl.load_demo_users
end