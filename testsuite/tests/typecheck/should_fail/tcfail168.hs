
-- Test trac #719 (shouldn't give the entire do block in the error message)

module ShouldFail where

foo = do
          putChar
          putChar 'a'
          putChar 'a'
          putChar 'a'
          putChar 'a'
          putChar 'a'
          putChar 'a'
          putChar 'a'
          putChar 'a'
          putChar 'a'
          putChar 'a'
          putChar 'a'
          putChar 'a'
          putChar 'a'
          putChar 'a'
          putChar 'a'
          putChar 'a'
          putChar 'a'
          putChar 'a'
          putChar 'a'
          putChar 'a'
          putChar 'a'
          putChar 'a'
          putChar 'a'
          putChar 'a'
          putChar 'a'
          putChar 'a'
          putChar 'a'
          putChar 'a'
          putChar 'a'
          putChar 'a'
          putChar 'a'
          putChar 'a'
          putChar 'a'
          putChar 'a'
          putChar 'a'
          putChar 'a'
          putChar 'a'
          putChar 'a'
          putChar 'a'
          putChar 'a'
          putChar 'a'
          putChar 'a'
          putChar 'a'
          putChar 'a'
          putChar 'a'
          putChar 'a'
          putChar 'a'
          putChar 'a'
          putChar 'a'
          putChar 'a'
          putChar 'a'
          putChar 'a'
          putChar 'a'
          putChar 'a'
          putChar 'a'
          putChar 'a'
          putChar 'a'
          putChar 'a'
