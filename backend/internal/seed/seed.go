package seed

import (
	_ "embed"

	"github.com/google/uuid"
)

//go:embed inception.jpg
var inceptionImage []byte

//go:embed 1984.jpg
var image1984 []byte

//go:embed eldenring.jpg
var eldenringImage []byte

//go:embed darknight.jpg
var darknightImage []byte

//go:embed radiohead.png
var radioheadImage []byte

// ImageID constants with fixed UUIDs used in iOS test data.
var (
	InceptionID  = uuid.MustParse("00000000-0000-0000-0001-000000000001")
	Image1984ID  = uuid.MustParse("00000000-0000-0000-0001-000000000002")
	EldenRingID  = uuid.MustParse("00000000-0000-0000-0001-000000000003")
	DarkKnightID = uuid.MustParse("00000000-0000-0000-0001-000000000004")
	RadioheadID  = uuid.MustParse("00000000-0000-0000-0001-000000000005")
)

// Images maps fixed seed image UUIDs to their embedded binary data.
var Images = map[uuid.UUID][]byte{
	InceptionID:  inceptionImage,
	Image1984ID:  image1984,
	EldenRingID:  eldenringImage,
	DarkKnightID: darknightImage,
	RadioheadID:  radioheadImage,
}
