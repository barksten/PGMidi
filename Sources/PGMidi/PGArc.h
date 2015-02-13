//
//  PGArc.h
//  PGMidi
//

#pragma once

//==============================================================================
// arc_cast

#ifdef __cplusplus

    template <typename OBJC_TYPE, typename SOURCE_TYPE>
    inline
    OBJC_TYPE *arc_cast(SOURCE_TYPE *source)
    {
        @autoreleasepool
        {
            return (__bridge OBJC_TYPE*)source;
        }
    }

#endif
