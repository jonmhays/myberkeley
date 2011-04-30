#!/usr/bin/env ruby

# TODO This is currently broken, since it refers to the old "sling_data_loader"
# (now called "ucb_data_loader").

require 'rubygems'
require 'optparse'
require 'active_record'
require 'oci8'
require 'json'
require 'digest/sha1'
require 'sling/sling'
require 'lib/sling/users'
require 'sling_data_loader'
include SlingInterface
include SlingUsers

module MyBerkeleyData
  PARTICIPANT_UIDS = ['308541','538733','772931','311120','561717','312951','761449','666227','772189','762641','313367','766739','766724','775123','727646','175303']
  ROLE_CODES = {1 => "Undergraduate Student", 2 => "Graduate Student", 3 => "GSI", 4 => "Instructor", 5 => "Staff"}
  UG_GRAD_FLAG_MAP = {:U => 'Undergraduate Student', :G => 'Graduate Student'}
  class OracleDataLoader

    @env = nil
    
    @user_manager = nil
    @sling = nil
    @num_students = nil
    @user_password_key = nil
    
    @oracle_host = nil
    @oracle_user = nil
    @oracle_password = nil
    @oracle_sid = nil
    
    @sling_data_loader = nil
    
    attr_reader :oracle_host, :oracle_user, :oracle_password, :oracle_sid, :user_password_key, :num_students, :sling_data_loader
    
    def initialize(options)
      @oracle_host = options[:oraclehost]
      @oracle_user = options[:oracleuser]
      @oracle_password = options[:oraclepwd]
      @oracle_sid = options[:oraclesid]
      
      @env = options[:runenv]
      @user_password_key = options[:userpwdkey]
      @num_students = options[:numstudents]
      @sling = Sling.new(options[:appserver], options[:adminpwd], true)
      @sling.do_login
      @user_manager = UserManager.new(@sling)
      @sling_data_loader = MyBerkeleyData::SlingDataLoader.new(options[:appserver], options[:adminpwd], 0) # no random users, just real ones
      
      ActiveRecord::Base.logger = Logger.new(STDOUT)
      #requires a TNSNAMES.ORA file and a TNS_ADMIN env variable pointing to directory containing it
      conn = ActiveRecord::Base.establish_connection(
          :adapter  => "oracle_enhanced",
          #:host     => odl.oracle_host,
          #:port     => 1523,
          :username => @oracle_user,
          :password => @oracle_password,
          :database => @oracle_sid
         )
    end
    
      #email = user_props['email'] || ""
      #firstname = user_props['firstName']  || ""
      #lastname = user_props['lastName'] || ""
      #role = user_props['role'] || ""
      #department = user_props['department'] || ""
      #college = user_props['college'] || ""
      #major = user_props['major'] || ""
      #context = user_props['context'] || ""
      #standing = user_props['standing'] || ""
      #participant = user_props['participant'] || ""
    def make_user_props(ced_student)
      user_props = {}
      user_props['firstName'] = ced_student.first_name.strip
      user_props['lastName'] = ced_student.last_name.strip
      user_props['email'] = make_email ced_student
      determine_role user_props, ced_student
      determine_college user_props, ced_student
      determine_department user_props, ced_student
      determine_major user_props, ced_student
      determine_current_status user_props, ced_student
      user_props['context'] = ['g-ced-students']
      determine_standing user_props, ced_student 
      return user_props
    end
    
    def determine_standing(user_props, ced_student)
      if ('U'.eql?ced_student.ug_grad_flag.strip )
        user_props['standing'] = 'undergrad'
      elsif ('G'.eql?ced_student.ug_grad_flag.strip)
        user_props['standing'] = 'grad'
      else
        user_props['standing'] = 'unknown'
      end
    end
    
    def determine_major(user_props, ced_student)
      if ('DOUBLE'.eql?ced_student.major_name.strip)
        if ('ENV DSGN'.eql?ced_student.college_abbr2.strip)
          user_props['major'] = [ced_student.major_name2.strip.sub(/&/, 'AND')]
        end
        if (('ENV DSGN'.eql?ced_student.college_abbr3.strip))
          user_props['major'] = [ced_student.major_name3.strip.sub(/&/, 'AND')]
        end
      else
        user_props['major'] = [ced_student.major_name.strip.sub(/&/, 'AND')]
      end
    end
    
    # STUDENT-TYPE-REGISTERED,EMPLOYEE-STATUS-EXPIRED
    def is_current(ced_student)
      if (ced_student.affiliations.include? "STUDENT-TYPE-REGISTERED")
        return true
      else
        return false
      end
    end
    
    def determine_current_status(user_props, ced_student)
      if (is_current ced_student )
        user_props['current'] = true;
      else
        user_props['current'] = false
      end
    end
    
    
    def determine_role(user_props, ced_student)
      role = UG_GRAD_FLAG_MAP[ced_student.ug_grad_flag.to_sym]
      return role
    end
    
    def determine_department(user_props, ced_student)
      user_props['department'] = '' # need the empty string for profile page trimpath template handling
    end
    
    def determine_college(user_props, ced_student)
      user_props['college'] = 'College of Environmental Design'
    end
    
    def make_email ced_student
      if (ENV_PROD.eql?@env) 
        email = ced_student.student_email_address
      else #obfuscate the email
        email = "#{ced_student.first_name.gsub(/\s*/,'').downcase}.#{ced_student.last_name.gsub(/\s*/,'').downcase}@berkeley.edu"
      end
      return email
    end
    
    def select_ced_students
      ced_students =  MyBerkeleyData::Student.find_by_sql "select * from BSPACE_STUDENT_INFO_VW si
                left join BSPACE_STUDENT_MAJOR_VW sm on si.STUDENT_LDAP_UID = sm.LDAP_UID
                where (sm.COLLEGE_ABBR = 'ENV DSGN' or sm.COLLEGE_ABBR2 = 'ENV DSGN' or sm.COLLEGE_ABBR3 = 'ENV DSGN' or sm.COLLEGE_ABBR4 = 'ENV DSGN')
                and si.AFFILIATIONS like '%STUDENT-TYPE-REGISTERED%'"
      return ced_students
    end
    
    def load_ced_students

      ced_students = select_ced_students
      i = 0
      ced_students.each do |s|
        props = make_user_props s
        if (@user_password_key)
          user_password = sling_data_loader.make_password s.stu_name, @user_password_key
        else
          user_password = "testuser"
        end
        if (props['current'] == true)
          student_ldap_uid = s.student_ldap_uid
          user = @sling_data_loader.load_user student_ldap_uid, props, user_password
          @sling_data_loader.add_student_to_group user
          @sling_data_loader.apply_student_aces user
          #break if (i += 1) >= @num_students
        end
      end
    end
  end
  

 
# STUDENT_LDAP_UID
#UG_GRAD_FLAG
#ROLE_CD
#STU_NAME
#STUDENT_EMAIL_ADDRESS
#EMAIL_DISCLOS_CD
#EDUC_LEVEL
#FIRST_NAME
#LAST_NAME
#STUDENT_ID
#AFFILIATIONS

  class Major < ActiveRecord::Base
    set_table_name "BSPACE_STUDENT_MAJOR_VW"
    set_primary_key "ldap_uid"
    belongs_to :student, :foreign_key => "student_ldap_uid"
  end
  
  class Student < ActiveRecord::Base
    set_table_name "BSPACE_STUDENT_INFO_VW"
    set_primary_key "student_ldap_uid"
  end
end

if ($PROGRAM_NAME.include? 'oracle_data_loader.rb')
  
  options = {}
  optparser = OptionParser.new do |opts|
    opts.banner = "Usage: oracle_data_loader.rb [options]"

    opts.on("-h", "--oraclehost OHOST", "Oracle Host") do |oh|
      options[:oraclehost] = oh
    end
    
    opts.on("-u", "--oracleuser OUSER", "Oracle User") do |ou|
      options[:oracleuser] = ou
    end
    
    opts.on("-p", "--oraclepwd OPWD", "Oracle Password") do |op|
      options[:oraclepwd] = op
    end
    
    opts.on("-i", "--oraclesid OSID", "Oracle SID") do |oi|
      options[:oraclesid] = oi
    end
    
    # trailing slash is mandatory
    options[:appserver] = "http://localhost:8080/" 
    opts.on("-a", "--appserver [APPSERVE]", "Application Server") do |as|
      options[:appserver] = as
    end
    
    options[:adminpwd] = "admin"
    opts.on("-q", "--adminpwd [ADMINPWD]", "Application Admin User Password") do |ap|
      options[:adminpwd] = ap
    end
    
    options[:runenv] = "dev"
    opts.on("-e", "--runenv [RUNENV]", "Runtime Environment") do |re|
      options[:runenv] = re
    end
    
    options[:numstudents] = 10
    opts.on("-n", "--numstudents [NUMSTUDENTS]", Integer, "Number of Students to load") do |ns|
      options[:numstudents] = ns
    end  

    opts.on("-k", "--userpwdkey USERPWDKEY", "Key used to encrypt user passwords") do |pk|
      options[:userpwdkey] = pk
    end      
  end
  
  optparser.parse ARGV
  
  odl = MyBerkeleyData::OracleDataLoader.new options
  
  
  odl.sling_data_loader.get_or_create_groups
  odl.sling_data_loader.load_defined_user_advisors
  odl.load_ced_students
  
end 