import React, { useState, useEffect } from 'react';
import { fetchNui } from '../utils/fetchNui';
import { useVisibility } from "../providers/VisibilityProvider";

import './App.css';

interface Offense {
  code: string;
  description: string;
  fine: number;
}

interface Player {
  id: string;
  name: string;
}

interface FormData {
  ticketUUID: string;
  offender_name: string;
  date: string;
  time: string;
  street: string;
  postal: string;
  license_plate: string;
  vehicle_make: string;
  vehicle_color: string;
  vehicle_type: string;
  speed: string;
  speed_zone: string;
  speed_type: string;
  officer_name: string;
  badge_number: string;
  agency: string;
  offense1_code: string;
  offense1_description: string;
  offense2_code: string;
  offense2_description: string;
  offense3_code: string;
  offense3_description: string;
  total_fine: number;
  officer_signature: string;
  offender_signature: string;
  notes: string;
  [key: string]: any; // Index signature for dynamic keys
}

const App: React.FC = () => {
  const [formData, setFormData] = useState<FormData>({
    ticketUUID: '',
    offender_name: '',
    date: '',
    time: '',
    street: '',
    postal: '',
    license_plate: '',
    vehicle_make: '',
    vehicle_color: '',
    vehicle_type: '',
    speed: '',
    speed_zone: '',
    speed_type: 'Visual',
    officer_name: '',
    badge_number: '',
    agency: 'LSPD',
    offense1_code: '',
    offense1_description: '',
    offense2_code: '',
    offense2_description: '',
    offense3_code: '',
    offense3_description: '',
    total_fine: 0,
    officer_signature: '',
    offender_signature: '',
    notes: '',
  });

  const [offenses, setOffenses] = useState<Offense[]>([]);
  const [players, setPlayers] = useState<Player[]>([]);
  const [filteredPlayers, setFilteredPlayers] = useState<Player[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [isFormPopulated, setIsFormPopulated] = useState(false);
  const [manualTotalFine, setManualTotalFine] = useState<number | null>(null);
  const isFieldDisabled = isFormPopulated;

  const { visible } = useVisibility();

  useEffect(() => {
    if (!visible) return;
    const fetchOffensesAndPlayers = async () => {
      try {
        const [offensesData, playersData, officerData] = await Promise.all([
          fetchNui<Offense[]>('getOffenses'),
          fetchNui<Player[]>('getPlayers'),
          fetchNui<{ officer_name: string; badge_number: string }>('getOfficer'),
        ]);

        if (Array.isArray(offensesData)) {
          setOffenses(offensesData);
        } else {
          console.error('Unexpected offenses data format', offensesData);
          setError('Unexpected data format');
        }

        if (Array.isArray(playersData)) {
          setPlayers(playersData);
        } else {
          console.error('Unexpected players data format', playersData);
          setError('Unexpected data format');
        }

        if (officerData) {
          setFormData(prevData => ({
            ...prevData,
            officer_name: officerData.officer_name,
            badge_number: officerData.badge_number
          }));
        } else {
          console.error('Error fetching officer data');
          setError('Error fetching officer data');
        }
      } catch (error) {
        console.error('Error fetching data:', error);
        setError('Error fetching data');
      } finally {
        setIsLoading(false);
      }
    };

    fetchOffensesAndPlayers();
  }, [visible]);

  useEffect(() => {
    const handlePopulateForm = (event: MessageEvent<any>) => {
      if (event.data.action === 'populateForm') {
        const data: FormData = event.data.data;
        if (data.ticketUUID) {
          setFormData(prevData => ({
            ...prevData,
            ...data
          }));
          setIsFormPopulated(true);
        }
      }
    };
  
    window.addEventListener('message', handlePopulateForm as EventListener);
  
    return () => {
      window.removeEventListener('message', handlePopulateForm as EventListener);
    };
  }, []);  

  useEffect(() => {
    const keyHandler = async (e: KeyboardEvent) => {
      if (e.code === "Escape") {
        try {
          if(isFieldDisabled) {
            setManualTotalFine(0);
            setFormData({
              ticketUUID: '',
              offender_name: '',
              date: '',
              time: '',
              street: '',
              postal: '',
              license_plate: '',
              vehicle_make: '',
              vehicle_color: '',
              vehicle_type: '',
              speed: '',
              speed_zone: '',
              speed_type: 'Visual',
              officer_name: '',
              badge_number: '',
              agency: 'LSPD',
              offense1_code: '',
              offense1_description: '',
              offense2_code: '',
              offense2_description: '',
              offense3_code: '',
              offense3_description: '',
              total_fine: 0,
              officer_signature: '',
              offender_signature: '',
              notes: '',
            });
            setIsFormPopulated(false);
          }
  
          // const { offender_signature, ticketUUID } = formData;
          // const response = await fetchNui("updateCitation", { offender_signature, ticketUUID });
          const response = await fetchNui("updateCitation", { formData });
          console.log('Form data response:', response);
        } catch (error) {
          console.error('Error fetching form data:', error);
        }
      }
    };
  
    window.addEventListener("keydown", keyHandler);
  
    return () => window.removeEventListener("keydown", keyHandler);
  }, [formData, isFieldDisabled]);  
  

  const calculateTotalFine = (updatedFormData: FormData) => {
    const getOffenseFine = (code: string) => {
      const offense = offenses.find(offense => offense.code === code);
      return offense ? Number(offense.fine) : 0;
    };
  
    const offenseCodes = [
      updatedFormData.offense1_code,
      updatedFormData.offense2_code,
      updatedFormData.offense3_code
    ];
  
    // Get the fines for each offense code
    const fines = offenseCodes.map(code => getOffenseFine(code));
  
    // Check if "Speeding (/calcticket)" is one of the selected offense descriptions
    const isSpeedingSelected = offenseCodes.some((code, index) => {
      return updatedFormData[`offense${index + 1}_description`] === "Speeding (/calcticket)";
    });
  
    // Calculate total fine
    let totalFine = fines.reduce((total, fine) => total + (isNaN(fine) ? 0 : fine), 0);
  
    // Deduct if speeding selected and there are multiple offenses
    if (!isFieldDisabled && offenseCodes.length > 1 && isSpeedingSelected) {
      totalFine -= 750; // Deduct 750 from the total fine
    }
    return totalFine; // Return total without manual fine for now
  };
  
  const handleChange = (e: React.ChangeEvent<HTMLInputElement | HTMLSelectElement | HTMLTextAreaElement>) => {
    const { name, value } = e.target;
  
    setFormData(prevData => {
      const updatedFormData = { ...prevData, [name]: value };
  
      // If the user manually changes the total fine
      if (name === 'total_fine') {
        const manualFine = value ? Number(value) : 0;
        setManualTotalFine(manualFine); // Store the manual fine value
        return { ...updatedFormData }; // Just return updated data without modifying total_fine here
      }
  
      // Calculate the total fine from offenses only
      const offenseTotalFine = calculateTotalFine(updatedFormData);
      const newTotalFine = offenseTotalFine + (manualTotalFine !== null ? manualTotalFine : 0);
  
      return { ...updatedFormData, total_fine: newTotalFine }; // Update total fine.
    });
  };
  
  const handleOffenseSelect = (e: React.ChangeEvent<HTMLSelectElement>, index: number) => {
    const selectedDescription = e.target.value;
    const selectedOffense = offenses.find(offense => offense.description === selectedDescription);
    
    if (selectedOffense) {
      setFormData(prevData => {
        const updatedFormData = {
          ...prevData,
          [`offense${index}_code`]: selectedOffense.code,
          [`offense${index}_description`]: selectedOffense.description,
        };
  
        // Calculate the total fine considering both manual and offense fines
        const offenseTotalFine = calculateTotalFine(updatedFormData);
        const newTotalFine = offenseTotalFine + (manualTotalFine !== null ? manualTotalFine : 0);
  
        return { ...updatedFormData, total_fine: newTotalFine };
      });
    }
  };

  const handleOffenseCodeChange = (e: React.ChangeEvent<HTMLInputElement>, index: number) => {
    const selectedCode = e.target.value;
    const selectedOffense = offenses.find(offense => offense.code === selectedCode);
    if (selectedOffense) {
      setFormData(prevData => ({
        ...prevData,
        [`offense${index}_code`]: selectedOffense.code,
        [`offense${index}_description`]: selectedOffense.description,
      }));
    }
  };

  const handlePlayerInput = (e: React.ChangeEvent<HTMLInputElement>) => {
    const query = e.target.value.toLowerCase();
    setFormData({ ...formData, offender_name: e.target.value });

    if (players.length > 0) {
      const filtered = players.filter(player => player.name.toLowerCase().includes(query));
      setFilteredPlayers(filtered);
    } else {
      setFilteredPlayers([]);
    }
  };

  const handlePlayerSelect = (player: Player) => {
    setFormData({ ...formData, offender_name: player.name });
    setFilteredPlayers([]);
  };
  
  const handleSubmit = async (e: React.FormEvent) => {
	  e.preventDefault();
	  if (!formData.offender_name || !formData.date || !formData.time) {
		setError('Please fill in all required fields.');
		return;
	  }

	  setIsSubmitting(true);

	  try {
		// Send the manual total fine if it exists, otherwise use the calculated total fine
		const finalTotalFine = manualTotalFine !== null ? manualTotalFine : formData.total_fine;

		const response = await fetchNui('scanTicket', { ...formData, total_fine: finalTotalFine });
		// Handle the response as needed
	  } catch (error) {
		console.error('Error invoking NUI callback:', error);
	  } finally {
		setIsSubmitting(false);
	  }
   };

  const getVisibility = (fieldCode: string | undefined, fieldDescription: string | undefined): boolean => {
    // Check if the form is populated
    if (isFormPopulated) {
      // Hide fields if they are not filled when form is populated
      return !!fieldCode || !!fieldDescription;
    }
    // Show fields if the form is not populated
    return true;
  };

  return (
    <div className="nui-wrapper">
      <div className="ticket-form-container">
        <div className="ticket-form">
          <h1 className="form-title">The State of San Andreas<br/>Traffic Citation</h1>
          <h3 className="form-subtitle"><i>Payment is <u><b>required</b></u> no later than <u><b>7-days</b></u> from the date of this violation.</i></h3>
          {error && (
            <div className="error">
              <p>{error}</p>
            </div>
          )}
          {isLoading ? (
            <p>Loading data...</p>
          ) : (
            <form onSubmit={handleSubmit}>
              <div className="player-input-container">
                <label htmlFor="offender_name">Offender's Name</label>
                <input
                  type="text"
                  name="offender_name"
                  id="offender_name"
                  value={formData.offender_name}
                  onChange={handlePlayerInput}
                  disabled={isFieldDisabled}
                />
                {filteredPlayers.length > 0 && (
                  <ul className="player-suggestions">
                    {filteredPlayers.map(player => (
                      <li key={player.id} onClick={() => handlePlayerSelect(player)}>
                        {player.name}
                      </li>
                    ))}
                  </ul>
                )}
              </div>
              <div className="form-group">
                <label htmlFor="date">Date</label>
                <input
                  type="date"
                  name="date"
                  id="date"
                  value={formData.date}
                  onChange={handleChange}
                  disabled={isFieldDisabled}
                />
              </div>
              <div className="form-group">
                <label htmlFor="time">Time</label>
                <input
                  type="time"
                  name="time"
                  id="time"
                  value={formData.time}
                  onChange={handleChange}
                  disabled={isFieldDisabled}
                />
              </div>
              <div className="form-group">
                <label htmlFor="street">Street</label>
                <input
                  type="text"
                  name="street"
                  id="street"
                  value={formData.street}
                  onChange={handleChange}
                  disabled={isFieldDisabled}
                />
              </div>
              <div className="form-group">
                <label htmlFor="postal">Postal Code</label>
                <input
                  type="text"
                  name="postal"
                  id="postal"
                  value={formData.postal}
                  onChange={handleChange}
                  disabled={isFieldDisabled}
                />
              </div>
              <div className="form-group">
                <label htmlFor="license_plate">License Plate</label>
                <input
                  type="text"
                  name="license_plate"
                  id="license_plate"
                  value={formData.license_plate}
                  onChange={handleChange}
                  disabled={isFieldDisabled}
                />
              </div>
              <div className="form-group">
                <label htmlFor="vehicle_make">Vehicle Make & Model</label>
                <input
                  type="text"
                  name="vehicle_make"
                  id="vehicle_make"
                  value={formData.vehicle_make}
                  onChange={handleChange}
                  placeholder='Ex: Bravado Buffalo STX'
                  disabled={isFieldDisabled}
                />
              </div>
              <div className="form-group">
                <label htmlFor="vehicle_color">Vehicle Color</label>
                <input
                  type="text"
                  name="vehicle_color"
                  id="vehicle_color"
                  value={formData.vehicle_color}
                  onChange={handleChange}
                  disabled={isFieldDisabled}
                />
              </div>
              <div className="form-group">
                <label htmlFor="vehicle_type">Vehicle Type</label>
                <input
                  type="text"
                  name="vehicle_type"
                  id="vehicle_type"
                  value={formData.vehicle_type}
                  onChange={handleChange}
                  placeholder='Ex: Sedan, Coupe, SUV, Truck, Van, Motorcycle, Commercial, Emergency'
                  disabled={isFieldDisabled}
                />
              </div>
              <div className="form-group">
                <label htmlFor="speed">Speed Traveled (MPH)</label>
                <input
                  type="text"
                  name="speed"
                  id="speed"
                  value={formData.speed}
                  onChange={handleChange}
                  disabled={isFieldDisabled}
                />
              </div>
              <div className="form-group">
                <label htmlFor="speed_zone">Speed Limit (MPH)</label>
                <input
                  type="text"
                  name="speed_zone"
                  id="speed_zone"
                  value={formData.speed_zone}
                  onChange={handleChange}
                  disabled={isFieldDisabled}
                />
              </div>
              <div className="form-group">
                <label htmlFor="speed_type">Type of Enforcement</label>
                <select
                  name="speed_type"
                  id="speed_type"
                  value={formData.speed_type}
                  onChange={handleChange}
                  disabled={isFieldDisabled}
                >
                  <option value="Visual">Visual</option>
                  <option value="Radar">Radar</option>
                  <option value="Lidar">Lidar</option>
                </select>
              </div>
              <div className="form-group">
                <label htmlFor="officer_name">Officer Name</label>
                <input
                  type="text"
                  id="officer_name"
                  name="officer_name"
                  value={formData.officer_name}
                  onChange={handleChange}
                  disabled={isFormPopulated}
                />
                <label htmlFor="badge_number">Badge Number</label>
                <input
                  type="text"
                  id="badge_number"
                  name="badge_number"
                  value={formData.badge_number}
                  onChange={handleChange}
                  disabled={isFormPopulated}
                />
                <label htmlFor="agency">Agency</label>
                <select
                  name="agency"
                  id="agency"
                  value={formData.agency}
                  onChange={handleChange}
                  disabled={isFieldDisabled}
                >
                  <option value="LSPD">LSPD</option>
                  <option value="BCSO/LSCSO">BCSO/LSCSO</option>
                  <option value="SAST">SAST</option>
                </select>
              </div>
              {getVisibility(formData.offense1_code, formData.offense1_description) && (
                <div className="form-group">
                  <label htmlFor="offense1_code">Offense Code</label>
                  <input
                    type="text"
                    name="offense1_code"
                    value={formData.offense1_code || ''}
                    onChange={(e) => handleOffenseCodeChange(e, 1)}
                    disabled={isFieldDisabled}
                  />
                  <label htmlFor="offense1_description">Offense Description</label>
                  <select
                    name="offense1_description"
                    id="offense1_description"
                    value={formData.offense1_description || ''}
                    onChange={(e) => handleOffenseSelect(e, 1)}
                    disabled={isFieldDisabled}
                  >
                    <option value="">Select offense</option>
                    {offenses.map(offense => (
                      <option key={offense.code} value={offense.description}>
                        {offense.description}
                      </option>
                    ))}
                  </select>
                </div>
              )}
              {getVisibility(formData.offense2_code, formData.offense2_description) && (
                <div className="form-group">
                  <label htmlFor="offense2_code">Offense Code</label>
                  <input
                    type="text"
                    name="offense2_code"
                    value={formData.offense2_code || ''}
                    onChange={(e) => handleOffenseCodeChange(e, 2)}
                    disabled={isFieldDisabled}
                  />
                  <label htmlFor="offense2_description">Offense Description</label>
                  <select
                    name="offense2_description"
                    id="offense2_description"
                    value={formData.offense2_description || ''}
                    onChange={(e) => handleOffenseSelect(e, 2)}
                    disabled={isFieldDisabled}
                  >
                    <option value="">Select offense</option>
                    {offenses.map(offense => (
                      <option key={offense.code} value={offense.description}>
                        {offense.description}
                      </option>
                    ))}
                  </select>
                </div>
              )}
              {getVisibility(formData.offense3_code, formData.offense3_description) && (
                <div className="form-group">
                  <label htmlFor="offense3_code">Offense Code</label>
                  <input
                    type="text"
                    name="offense3_code"
                    value={formData.offense3_code || ''}
                    onChange={(e) => handleOffenseCodeChange(e, 3)}
                    disabled={isFieldDisabled}
                  />
                  <label htmlFor="offense3_description">Offense Description</label>
                  <select
                    name="offense3_description"
                    id="offense3_description"
                    value={formData.offense3_description || ''}
                    onChange={(e) => handleOffenseSelect(e, 3)}
                    disabled={isFieldDisabled}
                  >
                    <option value="">Select offense</option>
                    {offenses.map(offense => (
                      <option key={offense.code} value={offense.description}>
                        {offense.description}
                      </option>
                    ))}
                  </select>
                </div>
              )}
              <div className="form-group">
                <label htmlFor="total_fine">Total Fine</label>
                <input
                  type="number"
                  name="total_fine"
                  id="total_fine"
                  value={formData.total_fine}
                  onChange={handleChange}
                  disabled={isFieldDisabled}
                />
              </div>
              <div className="form-group">
                <label htmlFor="officer_signature">Officer Signature</label>
                <input
                  type="text"
                  name="officer_signature"
                  id="officer_signature"
                  value={formData.officer_signature}
                  onChange={handleChange}
                  disabled={isFieldDisabled}
                />
              </div>
              <div className="form-group">
                <label htmlFor="offender_signature">Offender Signature</label>
                <input
                  type="text"
                  name="offender_signature"
                  id="offender_signature"
                  value={formData.offender_signature}
                  onChange={handleChange}
                />
              </div>
              {getVisibility(formData.notes, undefined) && (
                <div className="form-group">
                  <label htmlFor="notes">Notes</label>
                  <textarea
                    name="notes"
                    id="notes"
                    value={formData.notes || ''}
                    onChange={handleChange}
                    disabled={isFieldDisabled}
                  />
                </div>
              )}
              <div className="form-group">
                <button type="submit" disabled={isFieldDisabled}>
                  {isSubmitting ? 'Submitting...' : 'Submit'}
                </button>
              </div>
            </form>
          )}
        </div>
      </div>
    </div>
  );
};

export default App;