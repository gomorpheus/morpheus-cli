require 'morpheus/cli/mixins/print_helper'
require 'morpheus/cli/option_types'
require 'morpheus/rest_client'
# Mixin for Morpheus::Cli command classes 
# Provides common methods for infrastructure management
module Morpheus::Cli::InfrastructureHelper

	def self.included(klass)
		klass.send :include, Morpheus::Cli::PrintHelper
	end

	def groups_interface
		# @api_client.groups
		raise "#{self.class} has not defined @groups_interface" if @groups_interface.nil?
		@groups_interface
	end

	def clouds_interface
		# @api_client.clouds
		raise "#{self.class} has not defined @clouds_interface" if @clouds_interface.nil?
		@clouds_interface
	end

	def find_group_by_name_or_id(val)
		if val.to_s =~ /\A\d{1,}\Z/
			return find_group_by_id(val)
		else
			return find_group_by_name(val)
		end
	end

	def find_group_by_id(id)
		begin
			json_response = groups_interface.get(id.to_i)
			return json_response['group']
		rescue RestClient::Exception => e
			if e.response && e.response.code == 404
				print_red_alert "Group not found by id #{id}"
				exit 1
			else
				raise e
			end
		end
	end

	def find_group_by_name(name)
		json_results = groups_interface.get({name: name})
		if json_results['groups'].empty?
			print_red_alert "Group not found by name #{name}"
			exit 1
		end
		group = json_results['groups'][0]
		return group
	end

	def find_cloud_by_name_or_id(val)
		if val.to_s =~ /\A\d{1,}\Z/
			return find_cloud_by_id(val)
		else
			return find_cloud_by_name(val)
		end
	end

	def find_cloud_by_id(id)
		json_results = clouds_interface.get(id.to_i)
		if json_results['zone'].empty?
			print_red_alert "Cloud not found by id #{id}"
			exit 1
		end
		cloud = json_results['zone']
		return cloud
	end

	def find_cloud_by_name(name)
		json_results = clouds_interface.get({name: name})
		if json_results['zones'].empty?
			print_red_alert "Cloud not found by name #{name}"
			exit 1
		end
		cloud = json_results['zones'][0]
		return cloud
	end

	def get_available_cloud_types(refresh=false)
		if !@available_cloud_types || refresh
			@available_cloud_types = clouds_interface.cloud_types['zoneTypes']
		end
		return @available_cloud_types
	end

	def cloud_type_for_name_or_id(val)
		if val.to_s =~ /\A\d{1,}\Z/
			return cloud_type_for_id(val)
		else
			return cloud_type_for_name(val)
		end
	end
		def cloud_type_for_id(id)
		return get_available_cloud_types().find { |z| z['id'].to_i == id.to_i}
	end

	def cloud_type_for_name(name)
		return get_available_cloud_types().find { |z| z['name'].downcase == name.downcase || z['code'].downcase == name.downcase}
	end

end
