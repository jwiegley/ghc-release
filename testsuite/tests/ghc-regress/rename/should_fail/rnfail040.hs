-- This one should fail, because it exports 
-- both List:nub and Rnfail040_A:nub
--
-- 	List:nub        is in scope as M.nub and nub
--	Rnfail040_A:nub is in scope as T.nub, M.nub, and nub

module M1 (module M) where

 import qualified Rnfail040_A as M 	-- M.nub
 import List as M			-- M.nub nub
 import Rnfail040_A as T		-- T.nub nub
