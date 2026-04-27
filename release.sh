#! /bin/bash

VERSION=$(grep 'VERSION =' lib/tracelit/version.rb | awk -F'"' '{print $2}')

echo "Building gem..."
gem build tracelit.gemspec

echo "Pushing gem to RubyGems..."
gem push tracelit-${VERSION}.gem --host https://rubygems.org

echo "Cleaning up..."
rm tracelit-${VERSION}.gem

echo "Done!"