/* IBM_PROLOG_BEGIN_TAG                                                   */
/* This is an automatically generated prolog.                             */
/*                                                                        */
/* $Source: src/include/usr/sbe/sbeif.H $                                 */
/*                                                                        */
/* OpenPOWER HostBoot Project                                             */
/*                                                                        */
/* COPYRIGHT International Business Machines Corp. 2013,2014              */
/*                                                                        */
/* Licensed under the Apache License, Version 2.0 (the "License");        */
/* you may not use this file except in compliance with the License.       */
/* You may obtain a copy of the License at                                */
/*                                                                        */
/*     http://www.apache.org/licenses/LICENSE-2.0                         */
/*                                                                        */
/* Unless required by applicable law or agreed to in writing, software    */
/* distributed under the License is distributed on an "AS IS" BASIS,      */
/* WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or        */
/* implied. See the License for the specific language governing           */
/* permissions and limitations under the License.                         */
/*                                                                        */
/* IBM_PROLOG_END_TAG                                                     */
#ifndef _SBEIF_H
#define _SBEIF_H

#include <errl/errlentry.H>
#include <pnor/pnorif.H>

namespace SBE
{
    // Each SBE Image stored in PNOR has a 64-byte version associated with it
    // (like a SHA hash of the image)
    const size_t   SBE_IMAGE_VERSION_SIZE = 64; // 64 bytes

    typedef uint8_t sbe_image_version_t[SBE_IMAGE_VERSION_SIZE];


    /**
     * @brief Gets a pointer to the proper SBE image in PNOR
     *
     * @param[in] i_target     Target used to find right SBE Image in PNOR
     *
     * @param[out] o_imgPtr    Pointer to SBE Image mapped in PNOR
     *                         Note: Pointer moved past any header(s)
     *
     * @param[out] o_imgSize   Size of the SBE Image in PNOR
     *                         Note: Size does not include any header(s)
     *
     * @param[out] o_version   Pointer to SBE Image Version Struct
     *                         If Pointer is NULL, version not returned;
     *                         Else sbe_image_version_t is filled in
     *
     * @return errlHndl_t      Error log handle on failure.
     */
    errlHndl_t findSBEInPnor(TARGETING::Target* i_target,
                             void*& o_imgPt,
                             size_t& o_imgSize,
                             sbe_image_version_t* o_version = NULL);


    /**
     * @brief Iterates through all the functional processors and updates
     *        the SBE Image in a SEEPROM, if necessary.
     *
     * @return errlHndl_t    Error log handle on failure.
     */
    errlHndl_t updateProcessorSbeSeeproms();


} //end namespace SBE

#endif /* _SBEIF_H */
