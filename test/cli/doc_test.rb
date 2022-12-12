require 'morpheus_test'

# Tests for Morpheus::DocInterface
class MorpheusTest::DocTest < MorpheusTest::TestCase
  
  def test_doc_list
    assert_execute("doc list")
  end

  def test_doc_get
    # using --quiet because the output is massive
    assert_execute("doc get --quiet")
  end

  def test_doc_get_yaml
    # using --quiet because the output is massive
    assert_execute("doc get --yaml --quiet") 
  end

  # def test_doc_download
  #   assert_execute("doc download '/path/to/openapi.json')
  # end

  # def test_doc_download_yaml
  #   assert_execute("doc download '/path/to/openapi.yaml' --yaml")
  # end

  def test_doc_get_unauthorized
    # authentication is NOT required for this api
    without_authentication do
      assert_success("doc get -q")
    end
  end

end
