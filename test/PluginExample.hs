{-# LANGUAGE CPP #-}

#if __GLASGOW_HASKELL__ < 806

module PluginExample where
main :: IO ()
main = return ()

#elif mingw32_HOST_OS

module PluginExample where
import RecordDotPreprocessor() -- To check the plugin compiles
main :: IO ()
main = return ()

#else

{-# OPTIONS_GHC -fplugin=RecordDotPreprocessor -w #-}
{-# LANGUAGE DuplicateRecordFields, TypeApplications, FlexibleContexts, DataKinds, MultiParamTypeClasses, TypeSynonymInstances, FlexibleInstances #-}
module PluginExample where
#include "../examples/Both.hs"

#endif
