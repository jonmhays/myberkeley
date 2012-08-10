#!/usr/bin/env ruby

require 'rubygems'
require 'optparse'
require 'json'
require 'digest/sha1'
require 'logger'
require 'nakamura'
require 'nakamura/users'
require_relative 'ucb_data_loader'

## Block sling.rb's monkeying with form values.
module Net::HTTPHeader
  def encode_kvpair(k, vs)
    if vs.nil? or vs == '' then
      "#{urlencode(k)}="
    elsif vs.kind_of?(Array)
      # In Ruby 1.8.7, Array(string-with-newlines) will split the string
      # after each embedded newline.
      Array(vs).map {|v| "#{urlencode(k)}=#{urlencode(v.to_s)}" }
    else
      "#{urlencode(k)}=#{urlencode(vs.to_s)}"
    end
  end
end

module MyBerkeleyData
  class TagMigrator14
    attr_reader :ucb_data_loader, :log

    def initialize(options)
      @log = Logger.new(STDOUT)
      @log.level = Logger::DEBUG

      @tagged = []
      @tagmap = {
        "directory/agriculture_and_related_sciences" => "directory/veterinarysciencesagriculture",
        "directory/architecture" => "directory/architecturebuildingandplanning",
        "directory/architecture/architecture" => "directory/architecturebuildingandplanning/architecture",
        "directory/architecture/city_and_urban_planning" => "directory/architecturebuildingandplanning/planning",
        "directory/bio_med_sciences" => "directory/biologicalsciences",
        "directory/bio_med_sciences/biology" => "directory/biologicalsciences/biology",
        "directory/bio_med_sciences/botany_plant_biology" => "directory/biologicalsciences/botany",
        "directory/bio_med_sciences/conservation_biology" => "directory/biologicalsciences/othersinbiologicalsciences",
        "directory/bio_med_sciences/ecology" => "directory/biologicalsciences/othersinbiologicalsciences",
        "directory/bio_med_sciences/entomology" => "Entomology",
        "directory/bio_med_sciences/environmental_biology" => "directory/biologicalsciences/othersinbiologicalsciences",
        "directory/bio_med_sciences/genetics" => "directory/biologicalsciences/genetics",
        "directory/bio_med_sciences/marine_biology_and_biological_oceanography" => "Marine Biology",
        "directory/bio_med_sciences/microbiology" => "directory/biologicalsciences/microbiology",
        "directory/bio_med_sciences/nutrition" => "directory/biologicalsciences/othersinbiologicalsciences",
        "directory/bio_med_sciences/zoology_and_animal_biology" => "directory/biologicalsciences/zoology",
        "directory/col_groups" => "Collaborative Groups",
        "directory/departments" => nil,
        "directory/departments/ced" => "directory/collegeofenvironmentaldesign",
        "directory/departments/cnr" => "directory/collegeofnaturalresources",
        "directory/engineering" => "directory/engineering",
        "directory/law" => "directory/law",
        "directory/medicine_and_related_clinical_sciences" => "directory/medicineanddentistry",
        "directory/medicine_and_related_clinical_sciences/environmental_health" => "directory/medicineanddentistry",
        "directory/medicine_and_related_clinical_sciences/medicine" => "directory/medicineanddentistry",
        "directory/medicine_and_related_clinical_sciences/nursing" => "Nursing",
        "directory/medicine_and_related_clinical_sciences/optometry" => "Optometry",
        "directory/medicine_and_related_clinical_sciences/pharmacy" => "Pharmacy",
        "directory/medicine_and_related_clinical_sciences/physical_therapy" => "Physical Therapy",
        "directory/medicine_and_related_clinical_sciences/public_health" => "Public Health",
        "directory/medicine_and_related_clinical_sciences/veterinary_medicine" => "Veterinary Medicine",
        "directory/natural_resources_and_conservation" => nil,
        "directory/natural_resources_and_conservation/environmental_science" => "Environmental Science",
        "directory/natural_resources_and_conservation/environmental_studies" => "Environmental Studies",
        "directory/natural_resources_and_conservation/forestry" => "directory/veterinarysciencesagriculture/forestry",
        "directory/natural_resources_and_conservation/land_use_planning_and_management" => "Land Use Planning",
        "directory/natural_resources_and_conservation/natural_resources_management_policy" => "Natural Resources Management",
        "directory/natural_resources_and_conservation/urban_forestry" => "Urban Forestry",
        "directory/natural_resources_and_conservation/wildlife_and_wetlands_science" => "Wildlife & Wetlands",
        "directory/physical_sciences" => "directory/physicalsciences",
        "directory/physical_sciences/atmospheric_chemistry_and_climatology" => "directory/physicalsciences/othersinphysicalsciences",
        "directory/physical_sciences/hydrology_and_water_resources" => "directory/physicalsciences/othersinphysicalsciences",
        "directory/social_sciences" => "directory/socialstudies",
        "directory/social_sciences/economics" => "directory/socialstudies/economics",
        "directory/social_sciences/international_and_global_studies" => "directory/socialstudies/othersinsocialstudies",
        "directory/social_sciences/sociology" => "Sociology",
        "directory/social_sciences/urban_studies_and_affairs" => "Urban Studies",
        "directory/visual_and_performing_arts" => nil,
        "directory/visual_and_performing_arts/photography" => "Photography"
      }
      @ucb_data_loader = MyBerkeleyData::UcbDataLoader.new(options[:appserver], options[:adminpwd])
      @sling = @ucb_data_loader.sling
    end

    def collect_tagged
      res = @sling.execute_get(@sling.url_for('var/search/bytag.tidy.json?tag=directory*&page=0&items=400&_charset_=utf-8'))
      @log.info("Directory tag search returned #{res.code}, #{res.body}")
      json = JSON.parse(res.body)
      @tagged = json["results"]
    end

    def migrate_tagged
      @tagged.each do |item|
        @log.info("Item #{item['_path']} has tags #{item['sakai:tags']}")
        itemtype = item['sling:resourceType']
        oldtags = item['sakai:tags']
        if (itemtype == "sakai/pooled-content")
          itemid = item['_path']
          itempath = "p/#{itemid}"
          deleteitempaths = ["#{itempath}.update.html"]
        elsif (itemtype == "sakai/user-profile")
          itemid = item['userid']
          itempath = "~#{itemid}/public/authprofile"
          deleteitempaths = ["#{itempath}.update.html", "system/userManager/user/#{itemid}.update.html"]
        elsif (itemtype == "sakai/group-profile")
          itemid = item['sakai:group-id']
          itempath = "~#{itemid}/public/authprofile"
          deleteitempaths = ["#{itempath}.update.html", "system/userManager/user/#{itemid}.update.html"]
        else
          @log.warn("Skipping unknown type #{itemtype}")
          next
        end
        # First, delete the old tag properties.
        deleteitempaths.each do |path|
          @log.info("Delete tags at #{path}")
          res = @sling.execute_post(@sling.url_for(path), {
            "sakai:tags@Delete" => "",
            "sakai:tag-uuid@Delete" => ""
          })
          if (res.code != "200")
            @log.warn("Could not delete tags from #{path} : #{res.code}, #{res.body}")
            next
          end
        end
        # Then loop around the tag list, changing as needed.
        newtags = []
        oldtags.each do |oldtag|
          if (@tagmap.has_key?(oldtag))
            newtag = @tagmap[oldtag]
            if (!newtag.nil?)
              newtags.push("/tags/#{newtag}")
            end
          else
            newtags.push("/tags/#{oldtag}")
          end
        end
        # Then add the replacement tags.
        @log.info("Adding tags #{newtags.inspect}")
        newtags.each do |newtag|
          res = @sling.execute_post(@sling.url_for(itempath), {
            ":operation" => "tag",
            "key" => newtag
          })
          if (res.code != "200")
            @log.warn("Could not add tag #{newtag} to #{itempath} : #{res.code}, #{res.body}")
          end
        end
      end
    end
  end
end

begin
  options = {}
  optparser = OptionParser.new do |opts|
    opts.banner = "Usage: tagmigrator-1.4.0.rb -q ADMINPWD"
    # trailing slash is mandatory
    options[:appserver] = "http://localhost:8080/"
    opts.on("-a", "--appserver [APPSERVE]", "Application Server") do |as|
      options[:appserver] = as
    end
    options[:adminpwd] = "admin"
    opts.on("-q", "--adminpwd [ADMINPWD]", "Application Admin User Password") do |ap|
      options[:adminpwd] = ap
    end
  end

  optparser.parse ARGV
  migrator = MyBerkeleyData::TagMigrator14.new options
  start = Time.now
  migrator.log.info("loading started at #{start}")
  migrator.collect_tagged
  migrator.migrate_tagged
  finish = Time.now
  migrator.log.info("migration finised at #{finish}")
  migrator.log.info("migration took #{finish - start} seconds")
end
