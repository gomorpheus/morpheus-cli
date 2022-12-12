require 'morpheus_test'

# Tests for Morpheus::DocInterface
class MorpheusTest::DocInterfaceTest < MorpheusTest::TestCase
  
  def test_doc_list
    @doc_interface = client.doc
    response = @doc_interface.list()
    assert_equal response['links'].class, Array
  end

  def test_doc_get
    @doc_interface = client.doc
    response = @doc_interface.openapi()
    assert_equal response['openapi'], '3.0.3'
    # todo: fix this, can be cached and fail
    #assert_equal response['version'], Morpheus::Cli::Remote.load_remote(@config.remote_name)[:build_version]
  end

  def test_doc_get_yaml
    @doc_interface = client.doc
    response = @doc_interface.openapi({'format' => "yaml"})
    assert response.body
    assert YAML.load(response.body)
  end

  # def test_doc_download
  #   @doc_interface = client.doc
  #   response = @doc_interface.download_openapi('/path/to/openapi.json')
  #   yaml_content = response.body
  #   yaml_data = YAML.load(yaml_content)
  #   assert_not_nil yaml_data
  # end

end