FROM ruby:2.3.5

RUN gem install morpheus-cli

ENTRYPOINT ["morpheus"]