FROM ruby:2.5.1

RUN gem install morpheus-cli -v 4.2.18

ENTRYPOINT ["morpheus"]