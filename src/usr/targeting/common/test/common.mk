# IBM_PROLOG_BEGIN_TAG
# This is an automatically generated prolog.
#
# $Source: src/usr/targeting/common/test/common.mk $
#
# IBM CONFIDENTIAL
#
# COPYRIGHT International Business Machines Corp. 2012,2014
#
# p1
#
# Object Code Only (OCO) source materials
# Licensed Internal Code Source Materials
# IBM HostBoot Licensed Internal Code
#
# The source code for this program is not published or otherwise
# divested of its trade secrets, irrespective of what has been
# deposited with the U.S. Copyright Office.
#
# Origin: 30
#
# IBM_PROLOG_END_TAG

################################################################################
#
#  @file targeting/common/test/common.mk
#
#  @brief Common test makefile to be included in targeting/test/makefile
#
################################################################################

HWPF_INC_DIRS += fapi
HWPF_INC_DIRS += plat
HWPF_INC_DIRS += hwp

COMMON_TESTCASES += testcommontargeting.H

OBJS += ${COMMON_OBJS}
