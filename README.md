<img src="https://morpheusdata.com/wp-content/uploads/2020/04/morpheus-logo-v2.svg" width="200px">

# Morpheus CLI

- Website: https://www.morpheusdata.com/
- Guide: [Morpheus CLI Wiki](https://github.com/gomorpheus/morpheus-cli/wiki)
- Docs: [Morpheus CLI Documentation](https://clidocs.morpheusdata.com)
- Support: [Morpheus Support](https://support.morpheusdata.com)

This library is a Ruby gem that provides a command line interface for interacting with the Morpheus Data appliance. The features provided include provisioning clusters, hosts, and containers, deploying and monitoring applications, automating tasks, and much more.

## Installation

Install it using rubygems

    $ gem install morpheus-cli

Or add this line to your application's Gemfile:

    gem 'morpheus-cli'

And then execute:

    $ bundle install



## Usage

### morpheus command

This gem installs the [morpheus](https://github.com/gomorpheus/morpheus-cli/wiki/CLI-Manual) binary for running commands in your terminal shell. 

```sh
morpheus remote add demo https://demo.mymorpheus.com
morpheus instances list
```

### ruby code

If you are interested in interfacing with the Morpheus appliance in ruby directly, you can use [Morpheus::APIClient](https://github.com/gomorpheus/morpheus-cli/wiki/APIClient) or [Morpheus::Terminal](https://github.com/gomorpheus/morpheus-cli/wiki/Terminal).

For more detailed usage information, visit the [Morpheus CLI Wiki](https://github.com/gomorpheus/morpheus-cli/wiki).
