# Morpheus CLI

- Website: https://www.morpheusdata.com/
- Guide: [Morpheus CLI Wiki](https://github.com/gomorpheus/morpheus-cli/wiki)
- Docs: [Morpheus Documentation](https://docs.morpheusdata.com)
- Support: [Morpheus Support](https://support.morpheusdata.com)

<img src="https://www.morpheusdata.com/wp-content/uploads/2018/06/cropped-morpheus_highres.png" width="600px">

This library is a Ruby gem that provides a command line interface for interacting with the Morpheus Data appliance. The features provided include provisioning clusters, hosts, and containers, monitoring applications, infrastructure automating tasks, deployments, and much more.

## Installation

Add this line to your application's Gemfile:

    gem 'morpheus-cli'

And then execute:

    $ bundle install

Or install it yourself as:

    $ gem install morpheus-cli

## Usage

### morpheus binary

This gem installs the [morpheus](https://github.com/gomorpheus/morpheus-cli/wiki/CLI-Manual) binary for executing commands in your shell environment. 

```sh
morpheus remote add demo https://demo.mymorpheus.com
morpheus instances list
```

### ruby code

If you want to interface with your Morpheus appliance via ruby directly, you can use [Morpheus::APIClient](https://github.com/gomorpheus/morpheus-cli/wiki/APIClient) or [Morpheus::Terminal](https://github.com/gomorpheus/morpheus-cli/wiki/Terminal).

For more detailed usage information, visit the [Morpheus CLI Wiki](https://github.com/gomorpheus/morpheus-cli/wiki).
