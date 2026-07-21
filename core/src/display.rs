use sha2::{Digest, Sha256};

/// Compute a SHA-256 hash of an EDID block for resilient display identity.
/// This survives connector changes since the EDID is tied to the physical display.
pub fn compute_edid_hash(edid: &[u8]) -> String {
    let mut hasher = Sha256::new();
    hasher.update(edid);
    let result = hasher.finalize();
    hex::encode(&result)
}

/// Parse the manufacturer ID from EDID bytes 8-9.
/// The manufacturer ID is a 3-letter PNP ID encoded in 2 bytes as three 5-bit
/// groups, each in the range 1..=26 mapping to 'A'..='Z'. A group of 0 (or >26)
/// is not a valid PNP letter, so an out-of-range group makes the whole ID
/// invalid and yields `None` rather than emitting control/symbol garbage.
pub fn parse_manufacturer(edid: &[u8]) -> Option<String> {
    if edid.len() < 10 {
        return None;
    }
    let mfg = u16::from_be_bytes([edid[8], edid[9]]);
    let letter = |group: u16| -> Option<char> {
        let g = group & 0x1F;
        if (1..=26).contains(&g) {
            Some((g as u8 + b'A' - 1) as char)
        } else {
            None
        }
    };
    let c1 = letter(mfg >> 10)?;
    let c2 = letter(mfg >> 5)?;
    let c3 = letter(mfg)?;
    Some(format!("{c1}{c2}{c3}"))
}

/// Parse the model name from EDID descriptor blocks.
pub fn parse_model_name(edid: &[u8]) -> Option<String> {
    // EDID has 4 descriptor blocks starting at offset 54, each 18 bytes.
    // Monitor name is descriptor type 0xFC.
    for block_start in (54..126).step_by(18) {
        if edid.len() <= block_start + 18 {
            break;
        }
        let block = &edid[block_start..block_start + 18];
        if block[0] == 0 && block[1] == 0 && block[2] == 0 && block[3] == 0xFC && block[4] == 0 {
            // Monitor name string
            let name_bytes: Vec<u8> = block[5..]
                .iter()
                .copied()
                .take_while(|&b| b != 0x0A && b != 0x00)
                .collect();
            if !name_bytes.is_empty() {
                return Some(String::from_utf8_lossy(&name_bytes).trim().to_string());
            }
        }
    }
    None
}

/// Check if an EDID likely belongs to a Corsair Xeneon Edge.
/// The Xeneon Edge has 2560x720 or 720x2560 native resolution at 15.3" physical size.
pub fn is_xeneon_edge(edid: &[u8]) -> bool {
    // A base EDID block is 128 bytes. Anything shorter can't be parsed reliably,
    // and the size/resolution reads below would index out of bounds.
    if edid.len() < 128 {
        return false;
    }

    // Native resolution lives in the first Detailed Timing Descriptor at offset 54:
    //   horizontal addressable = low byte 56 | (high nibble of byte 58) << 8
    //   vertical addressable   = low byte 59 | (high nibble of byte 61) << 8
    // (The previous implementation read bytes 17-20, which are the manufacture
    // year / EDID version / basic-params - never the resolution.)
    let h_active = ((edid[58] as u16 & 0xF0) << 4) | edid[56] as u16;
    let v_active = ((edid[61] as u16 & 0xF0) << 4) | edid[59] as u16;

    // Xeneon Edge: 2560×720 or 720×2560
    let is_xeneon_res =
        (h_active == 2560 && v_active == 720) || (h_active == 720 && v_active == 2560);

    // Check physical size: typically ~15.3" (39cm) wide, ~4.3" (11cm) for landscape Xeneon Edge
    let width_cm = edid[21] as f64;
    let height_cm = edid[22] as f64;
    let is_xeneon_size = ((35.0..=42.0).contains(&width_cm) && (8.0..=13.0).contains(&height_cm))
        || ((8.0..=13.0).contains(&width_cm) && (35.0..=42.0).contains(&height_cm));

    // Check manufacturer
    let mfg = parse_manufacturer(edid);
    let is_corsair = mfg.as_deref() == Some("COR") || mfg.as_deref() == Some("CSR");

    is_xeneon_res || (is_xeneon_size && is_corsair)
}

// Simple hex encoding (no external dependency needed)
mod hex {
    pub fn encode(bytes: &[u8]) -> String {
        bytes.iter().map(|b| format!("{:02x}", b)).collect()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Create a minimal valid EDID block for testing.
    fn minimal_edid() -> Vec<u8> {
        let mut edid = vec![0u8; 128];
        // EDID header
        edid[0..8].copy_from_slice(&[0x00, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x00]);
        // Manufacturer: COR (Corsair)
        // C=0x03, O=0x0F, R=0x12
        // Encoded: ((C-'A'+1) << 10) | ((O-'A'+1) << 5) | (R-'A'+1)
        let mfg: u16 = ((3u16) << 10) | ((15u16) << 5) | 18u16;
        edid[8] = (mfg >> 8) as u8;
        edid[9] = (mfg & 0xFF) as u8;
        // Product code
        edid[10..12].copy_from_slice(&[0x01, 0x00]);
        // Serial
        edid[12..16].copy_from_slice(&[0x01, 0x00, 0x00, 0x00]);
        // Week / Year of manufacture (2026)
        edid[16] = 1;
        edid[17] = 26;
        // EDID version 1.4
        edid[18] = 1;
        edid[19] = 4;
        // Basic display params: digital input
        edid[20] = 0xA5;
        // Physical size at bytes 21 (H) / 22 (V) in cm.
        edid[21] = 39; // 39cm wide (~15.3")
        edid[22] = 11; // 11cm tall
        edid
    }

    /// Encode a native resolution into the first Detailed Timing Descriptor
    /// (offset 54) of a base EDID block, matching how `is_xeneon_edge` decodes it.
    fn set_dtd_resolution(edid: &mut [u8], h: u16, v: u16) {
        edid[56] = (h & 0xFF) as u8;
        edid[58] = ((h >> 4) & 0xF0) as u8;
        edid[59] = (v & 0xFF) as u8;
        edid[61] = ((v >> 4) & 0xF0) as u8;
    }

    #[test]
    fn test_compute_edid_hash_is_consistent() {
        let edid = minimal_edid();
        let hash1 = compute_edid_hash(&edid);
        let hash2 = compute_edid_hash(&edid);
        assert_eq!(hash1, hash2);
        assert_eq!(hash1.len(), 64); // SHA-256 hex
    }

    #[test]
    fn test_compute_edid_hash_differs_for_different_data() {
        let edid1 = minimal_edid();
        let mut edid2 = minimal_edid();
        edid2[12] = 0xFF; // Change serial
        assert_ne!(compute_edid_hash(&edid1), compute_edid_hash(&edid2));
    }

    #[test]
    fn test_parse_manufacturer() {
        let edid = minimal_edid();
        assert_eq!(parse_manufacturer(&edid), Some("COR".to_string()));
    }

    #[test]
    fn test_parse_manufacturer_short_input() {
        assert_eq!(parse_manufacturer(&[]), None);
        assert_eq!(parse_manufacturer(&[0; 9]), None);
    }

    #[test]
    fn test_is_xeneon_edge_with_size() {
        let edid = minimal_edid();
        // 39x11 cm → matches Xeneon landscape size range
        assert!(is_xeneon_edge(&edid));
    }

    #[test]
    fn test_is_xeneon_edge_by_resolution() {
        // A non-Corsair display that nonetheless reports the Edge's native
        // 720x2560 resolution should be detected via the DTD path alone.
        let mut edid = minimal_edid();
        // Neutralize manufacturer + size so only the resolution can match.
        edid[8] = 0x10;
        edid[9] = 0xAC; // "DEL"
        edid[21] = 60;
        edid[22] = 34;
        set_dtd_resolution(&mut edid, 720, 2560);
        assert!(is_xeneon_edge(&edid));

        // A completely different resolution must not match.
        set_dtd_resolution(&mut edid, 1920, 1080);
        assert!(!is_xeneon_edge(&edid));
    }

    #[test]
    fn test_is_xeneon_edge_short_edid() {
        assert!(!is_xeneon_edge(&[0; 10]));
        // A 127-byte buffer (one short of a base block) must not panic or match.
        assert!(!is_xeneon_edge(&[0; 127]));
    }

    /// Write an ASCII string into the descriptor block at `block_start` with the
    /// given descriptor type tag (0xFC = monitor name), matching how
    /// `parse_model_name` decodes it.
    fn set_descriptor(edid: &mut [u8], block_start: usize, tag: u8, text: &str) {
        edid[block_start] = 0;
        edid[block_start + 1] = 0;
        edid[block_start + 2] = 0;
        edid[block_start + 3] = tag;
        edid[block_start + 4] = 0;
        let bytes = text.as_bytes();
        for i in 0..13 {
            edid[block_start + 5 + i] = if i < bytes.len() { bytes[i] } else { 0x0A };
        }
    }

    #[test]
    fn test_parse_model_name() {
        let mut edid = minimal_edid();
        // Second descriptor block (offset 72) carries the monitor name.
        set_descriptor(&mut edid, 72, 0xFC, "XENEON EDGE");
        assert_eq!(parse_model_name(&edid), Some("XENEON EDGE".to_string()));
    }

    #[test]
    fn test_parse_model_name_absent_or_short() {
        // No 0xFC descriptor → None.
        assert_eq!(parse_model_name(&minimal_edid()), None);
        // Too-short buffers must not panic.
        assert_eq!(parse_model_name(&[]), None);
        assert_eq!(parse_model_name(&[0; 60]), None);
    }

    #[test]
    fn test_hex_encode() {
        assert_eq!(hex::encode(&[0xAB, 0xCD]), "abcd");
        assert_eq!(hex::encode(&[]), "");
    }

    #[test]
    fn test_is_xeneon_edge_landscape_2560x720() {
        // Portrait was covered above; verify the landscape native resolution.
        let mut edid = minimal_edid();
        // Neutralize manufacturer + size so only the resolution can match.
        edid[8] = 0x10;
        edid[9] = 0xAC; // "DEL"
        edid[21] = 60;
        edid[22] = 34;
        set_dtd_resolution(&mut edid, 2560, 720);
        assert!(is_xeneon_edge(&edid));
    }

    #[test]
    fn test_parse_model_name_in_each_descriptor_slot() {
        // The 0xFC monitor-name descriptor can live in any of the 4 base-block
        // descriptor slots (offsets 54, 72, 90, 108).
        for slot in [54usize, 72, 90, 108] {
            let mut edid = minimal_edid();
            set_descriptor(&mut edid, slot, 0xFC, "SLOTNAME");
            assert_eq!(
                parse_model_name(&edid),
                Some("SLOTNAME".to_string()),
                "monitor name not read from descriptor at offset {slot}"
            );
        }
    }

    #[test]
    fn test_parse_model_name_truncated_does_not_panic() {
        // Buffers that end partway through a descriptor block must not panic.
        for len in [54usize, 60, 71, 89, 125] {
            let edid = vec![0u8; len];
            let _ = parse_model_name(&edid);
        }
    }

    // --- BUG: parse_manufacturer emits non-alphabetic / control chars ---

    #[test]
    fn bug_parse_manufacturer_rejects_zero_group() {
        // Manufacturer bytes 8-9 == 0x0000 → every 5-bit group is 0, which maps
        // to (0 + b'A' - 1) = '@' (0x40), an invalid non-alphabetic code.
        let mut edid = vec![0u8; 128];
        edid[8] = 0x00;
        edid[9] = 0x00;
        let mfg = parse_manufacturer(&edid);
        // Correct behavior: an out-of-range (0) group is not a valid PNP letter,
        // so this should be rejected (None), not returned as "@@@".
        assert_eq!(
            mfg, None,
            "BUG: parse_manufacturer returned {mfg:?} instead of None for an invalid (0) group"
        );
    }

    #[test]
    fn bug_parse_manufacturer_only_emits_uppercase_letters() {
        // For a valid PNP id every character must be 'A'..='Z'. Feed an EDID
        // whose decoded groups include a 0 group and assert no control/symbol
        // characters leak out.
        let mut edid = vec![0u8; 128];
        // group1 = 1 ('A'), group2 = 0 ('@' - invalid), group3 = 1 ('A').
        // Explicit bit layout kept for documentation despite the zero group.
        #[allow(clippy::identity_op)]
        let mfg_bits: u16 = (1u16 << 10) | (0u16 << 5) | 1u16;
        edid[8] = (mfg_bits >> 8) as u8;
        edid[9] = (mfg_bits & 0xFF) as u8;
        if let Some(code) = parse_manufacturer(&edid) {
            assert!(
                code.chars().all(|c| c.is_ascii_uppercase()),
                "BUG: manufacturer code {code:?} contains non-alphabetic characters"
            );
        }
    }
}

#[cfg(test)]
mod proptests {
    use super::*;
    use proptest::prelude::*;

    proptest! {
        /// Arbitrary bytes must never panic and must produce bounded, well-formed,
        /// deterministic output across every display parser.
        #[test]
        fn display_parsers_are_panic_free_bounded_and_deterministic(bytes in prop::collection::vec(any::<u8>(), 0..300)) {
            let hash = compute_edid_hash(&bytes);
            // SHA-256 hex is always 64 lowercase hex chars, regardless of input.
            prop_assert_eq!(hash.len(), 64);
            prop_assert!(hash.chars().all(|c| c.is_ascii_hexdigit()));
            prop_assert_eq!(&hash, &compute_edid_hash(&bytes)); // deterministic

            let mfg = parse_manufacturer(&bytes);
            if let Some(ref m) = mfg {
                // A valid PNP id is exactly 3 uppercase letters.
                prop_assert_eq!(m.len(), 3);
                prop_assert!(m.chars().all(|c| c.is_ascii_uppercase()));
            }
            prop_assert_eq!(&mfg, &parse_manufacturer(&bytes)); // deterministic

            let model = parse_model_name(&bytes);
            prop_assert_eq!(&model, &parse_model_name(&bytes));

            // is_xeneon_edge is a pure predicate - deterministic, never panics.
            let edge = is_xeneon_edge(&bytes);
            prop_assert_eq!(edge, is_xeneon_edge(&bytes));
        }
    }
}
