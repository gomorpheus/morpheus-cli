FROM ruby:2.5.1

RUN gem install morpheus-cli -v 4.1.8

ENTRYPOINT ["morpheus"]