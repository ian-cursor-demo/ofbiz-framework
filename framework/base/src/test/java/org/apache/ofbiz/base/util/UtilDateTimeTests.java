/*
 * Licensed to the Apache Software Foundation (ASF) under one
 * or more contributor license agreements.  See the NOTICE file
 * distributed with this work for additional information
 * regarding copyright ownership.  The ASF licenses this file
 * to you under the Apache License, Version 2.0 (the
 * "License"); you may not use this file except in compliance
 * with the License.  You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing,
 * software distributed under the License is distributed on an
 * "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
 * KIND, either express or implied.  See the License for the
 * specific language governing permissions and limitations
 * under the License.
 */
package org.apache.ofbiz.base.util;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import java.sql.Timestamp;
import java.time.Instant;
import java.util.Locale;
import java.util.TimeZone;

import org.junit.Test;

public class UtilDateTimeTests {

    private static final TimeZone UTC = TimeZone.getTimeZone("UTC");

    private static Timestamp noon(String date) {
        return Timestamp.from(Instant.parse(date + "T12:00:00Z"));
    }

    @Test
    public void testIsWeekend() {
        assertTrue(UtilDateTime.isWeekend(noon("2026-10-03"), UTC, Locale.US));
        assertTrue(UtilDateTime.isWeekend(noon("2026-10-04"), UTC, Locale.US));
        assertFalse(UtilDateTime.isWeekend(noon("2026-10-02"), UTC, Locale.US));
        assertFalse(UtilDateTime.isWeekend(noon("2026-10-05"), UTC, Locale.US));
    }

    @Test
    public void testAddBusinessDays() {
        assertEquals(noon("2026-10-05"), UtilDateTime.addBusinessDays(noon("2026-10-05"), 0, UTC, Locale.US));
        assertEquals(noon("2026-10-09"), UtilDateTime.addBusinessDays(noon("2026-10-05"), 4, UTC, Locale.US));
        assertEquals(noon("2026-10-05"), UtilDateTime.addBusinessDays(noon("2026-10-02"), 1, UTC, Locale.US));
        assertEquals(noon("2026-10-06"), UtilDateTime.addBusinessDays(noon("2026-10-01"), 3, UTC, Locale.US));
    }

    @Test
    public void testGetBusinessDaysBetween() {
        assertEquals(5, UtilDateTime.getBusinessDaysBetween(noon("2026-10-05"), noon("2026-10-10"), UTC, Locale.US));
        assertEquals(10, UtilDateTime.getBusinessDaysBetween(noon("2026-10-05"), noon("2026-10-18"), UTC, Locale.US));
        assertEquals(0, UtilDateTime.getBusinessDaysBetween(null, noon("2026-10-18"), UTC, Locale.US));
        assertEquals(0, UtilDateTime.getBusinessDaysBetween(noon("2026-10-05"), null, UTC, Locale.US));
    }
}
